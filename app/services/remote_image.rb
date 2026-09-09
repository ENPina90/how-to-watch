# frozen_string_literal: true

require 'net/http'
require 'resolv'
require 'ipaddr'

# Fetches an image the user pasted a link to, without letting them aim the server at
# something that is not an image on the public internet.
#
# The poster picker used to hand the URL straight to `URI.open`, which was safe only
# because the URL was always one of the candidates the app had found for itself. A field
# somebody can type into is a different thing entirely, and `URI.open` is a poor place to
# put it:
#
#   * a string that is not a URL falls through to `File.open`, so "/etc/passwd" is read off
#     the disk and attached as a poster that everyone who can see the entry can then read;
#   * "http://169.254.169.254/..." reaches the cloud metadata service, and anything on
#     localhost or inside the private network is reachable the same way;
#   * the response is read whole, so a URL that streams forever exhausts memory;
#   * the content type is whatever the remote server claimed, and Active Storage serves it
#     back under that type -- image/svg+xml is a way to hand a viewer a script.
#
# So: http(s) only, the host resolved and every address checked before anything is opened,
# the connection pinned to the address that was checked, redirects followed by hand and
# re-checked at each hop, the body capped, and the type sniffed from the bytes rather than
# taken from the response.
class RemoteImage
  Result = Struct.new(:io, :content_type, :error, keyword_init: true) do
    def ok? = error.nil?
  end

  MAX_REDIRECTS = 3
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10

  # Everything that is not somewhere on the public internet. IPAddr answers for most of it,
  # but not for the ranges that route somewhere surprising rather than nowhere: the shared
  # address space carriers use, the benchmarking range, and 0.0.0.0/8, which several
  # platforms treat as "this host".
  BLOCKED_RANGES = [
    IPAddr.new('0.0.0.0/8'),        # this host
    IPAddr.new('100.64.0.0/10'),    # carrier-grade NAT
    IPAddr.new('192.0.0.0/24'),     # IETF protocol assignments
    IPAddr.new('198.18.0.0/15'),    # benchmarking
    IPAddr.new('::/128'),           # unspecified
    IPAddr.new('64:ff9b::/96')      # IPv4/IPv6 translation
  ].freeze

  def self.fetch(...) = new(...).fetch

  # `accept` is the set of content types worth having; anything else is an error rather
  # than something to attach and find out about later.
  def initialize(url, max_bytes:, accept:)
    @url = url.to_s.strip
    @max_bytes = max_bytes
    @accept = accept
  end

  def fetch
    uri = parse
    return failure('That does not look like an image address') if uri.nil?

    read_through_redirects(uri)
  rescue Net::OpenTimeout, Net::ReadTimeout
    failure('That address took too long to answer')
  rescue StandardError => e
    Rails.logger.warn("RemoteImage could not fetch #{@url}: #{e.class}: #{e.message}")
    failure('Could not fetch an image from that address')
  end

  private

  def failure(message) = Result.new(error: message)

  # http and https only. Everything else -- a bare path, file://, ftp:// -- is refused
  # here, which is the whole reason this does not go through URI.open.
  def parse
    uri = URI.parse(@url)
    return nil unless uri.is_a?(URI::HTTP) && uri.host.present?

    uri
  rescue URI::InvalidURIError
    nil
  end

  def read_through_redirects(uri)
    MAX_REDIRECTS.times do
      address = public_address_for(uri.host)
      return failure('That address is not one this server will fetch from') if address.nil?

      outcome, value = get(uri, address)
      return value unless outcome == :redirect

      return failure('That address redirects nowhere') if value.blank?

      # Resolved against the current URI so a relative Location works, and round the loop
      # so the new host is checked as strictly as the first one was.
      uri = URI.join(uri, value)
      return failure('That does not look like an image address') unless uri.is_a?(URI::HTTP)
    end

    failure('That address redirects too many times')
  end

  # The body is read inside the response block, chunk by chunk. Asking Net::HTTP for the
  # response first and reading afterwards would have it buffer the whole thing before the
  # cap below ever ran, which is the case the cap is for.
  #
  # Pinned to the address that was just checked, rather than handed the hostname to resolve
  # again. Otherwise a name that answers with a public address for the check and a private
  # one a moment later gets through -- the connection has to go to the address that was
  # actually vetted. The hostname stays on the request for Host and TLS.
  def get(uri, address)
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = address
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    http.start do |connection|
      connection.request(Net::HTTP::Get.new(uri)) do |response|
        return [:redirect, response['location']] if response.is_a?(Net::HTTPRedirection)

        unless response.is_a?(Net::HTTPSuccess)
          return [:done, failure('That address did not answer with an image')]
        end

        return [:done, read_capped(response)]
      end
    end
  end

  # One address for the host, or nil if any of them is somewhere this should not go. Any
  # rather than all: a name that resolves to both a public and a private address is a name
  # aimed at the private one.
  def public_address_for(host)
    addresses = resolve(host)
    return nil if addresses.empty?
    return nil unless addresses.all? { |address| public_address?(address) }

    addresses.first.to_s
  end

  def resolve(host)
    # A literal address is already resolved; Resolv would not answer for one.
    return [IPAddr.new(host)] if literal_address?(host)

    Resolv.getaddresses(host).filter_map do |address|
      IPAddr.new(address)
    rescue IPAddr::InvalidAddressError
      nil
    end
  rescue StandardError
    []
  end

  def literal_address?(host)
    IPAddr.new(host)
    true
  rescue IPAddr::InvalidAddressError
    false
  end

  def public_address?(address)
    # An IPv4 address wearing an IPv6 coat is still that address, and ::ffff:127.0.0.1
    # would otherwise pass every check below.
    address = address.native if address.ipv6? && address.ipv4_mapped?

    return false if address.loopback? || address.private? || address.link_local?
    return false if address.ipv4? && address.to_i >> 28 == 0xE # multicast
    return false if address.ipv6? && (address.to_s.start_with?('ff') || address.to_s == '::1')

    BLOCKED_RANGES.none? { |range| range.include?(address) }
  end

  # Read in chunks and stop at the cap, so a URL that streams without end costs one buffer
  # rather than the process.
  def read_capped(response)
    buffer = +''
    response.read_body do |chunk|
      buffer << chunk
      return failure('That image is too large') if buffer.bytesize > @max_bytes
    end

    verify(buffer)
  end

  # Sniffed from the bytes. What the server said it was sending is not evidence, and this
  # type is what Active Storage will serve the file back as.
  def verify(bytes)
    return failure('There was no image at that address') if bytes.empty?

    content_type = Marcel::MimeType.for(StringIO.new(bytes))
    return failure('That is not a JPEG, PNG, WebP or GIF') unless @accept.include?(content_type)

    Result.new(io: StringIO.new(bytes), content_type: content_type)
  end
end
