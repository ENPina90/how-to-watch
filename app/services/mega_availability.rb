# frozen_string_literal: true

require 'net/http'
require 'json'
require 'openssl'
require 'base64'

# Asks MEGA whether a link will actually play: that the file is there, and that the key in
# the link opens it.
#
# The check it replaces could not tell. UrlCheckerService calls a source healthy when its
# page has a <title>, and MEGA's embed page has none -- it is a 1.6KB shell that sets its
# title from JavaScript -- so every MEGA entry was marked broken the moment it was created,
# playable or not, and the cable schedule kept all of them off the dial. 381 of the 386
# marked broken on 2026-09-19 were fine.
#
# Two questions, both answered from one API call per fifty links:
#
#   Is the file there? The API's `g` command answers a file's size and its encrypted
#   attributes, or a negative error code. Asked without `g: 1` it issues no download URL,
#   so it costs no transfer quota -- which matters, because running out of that quota is
#   what stops a MEGA film partway through, and a sweep must not spend it.
#
#   Does the key open it? The attributes decrypt to text beginning "MEGA{" only under the
#   right key. A link whose key was truncated when it was pasted points at a file that
#   exists and that the player will never decrypt; asking only the first question would
#   call it working.
#
# Three states, as VidsrcAvailability has, and for the same reason: :unknown is "not
# answered" and must never be read as "broken". A MEGA outage or a rate limit would
# otherwise condemn the whole library in one sweep.
class MegaAvailability
  API = URI('https://g.api.mega.co.nz/cs')
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 15

  # How many links one request asks about. The API takes an array of commands and answers
  # an array in the same order; 424 links measured at nine requests.
  BATCH = 50

  # The answers that mean the link will not play, and nothing else does. Every other
  # negative code -- rate limits, "try again", internal errors -- is MEGA not answering, and
  # is :unknown. From MEGA's published error codes.
  GONE = {
    -2 => 'MEGA does not recognise the link',
    -9 => 'MEGA has no file at that link',
    -16 => 'MEGA has taken the file down'
  }.freeze

  Result = Struct.new(:state, :detail, keyword_init: true) do
    def available? = state == :available
    def missing? = state == :missing
    def unknown? = state == :unknown
  end

  # Whether this is the check for an entry. By the provider it resolves to, not its own
  # provider column: a channel set to MEGA plays its entries through MEGA whatever they say.
  def self.applies_to?(entry) = entry.resolved_source&.slug == 'mega'

  def for_entry(entry) = for_entries([entry]).fetch(entry.id)

  # { entry_id => Result } for any number of entries, fifty links to a request.
  def for_entries(entries)
    results = {}
    askable = []

    entries.each do |entry|
      link = parse(entry.source_key)
      if link.is_a?(Result)
        results[entry.id] = link
      else
        askable << [entry, link]
      end
    end

    askable.each_slice(BATCH).with_index do |batch, index|
      answers = ask(batch.map { |_, link| link[:handle] }, sequence: index)

      batch.each_with_index do |(entry, link), position|
        results[entry.id] = answers ? judge(answers[position], link[:key]) : unknown('MEGA did not answer')
      end
    end

    results
  end

  private

  # A stored key is `HANDLE#KEY`, sometimes with the player's options after a `!` or a `/`
  # (see Source#append_fragment_flag). A link with no handle or no key cannot play, so it is
  # not asked about; one whose key is merely damaged is asked, and fails at opens?.
  def parse(source_key)
    handle, fragment = source_key.to_s.split('#', 2)
    key = fragment.to_s.split(%r{[!/]}).first.to_s
    return missing('the link has no file handle') if handle.blank?
    return missing('the link has no key') if key.empty?

    { handle: handle, key: key }
  end

  def ask(handles, sequence:)
    uri = API.dup
    uri.query = URI.encode_www_form(id: sequence)
    body = handles.map { |handle| { a: 'g', p: handle } }.to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                                   open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.post(uri, body, 'Content-Type' => 'application/json')
    end
    return nil unless response.code.to_i == 200

    answers = JSON.parse(response.body)
    # The whole request refused comes back as one bare code rather than an array -- a rate
    # limit, typically. That is MEGA not answering about any of these links.
    answers.is_a?(Array) && answers.size == handles.size ? answers : nil
  rescue StandardError => e
    Rails.logger.error "MEGA availability request failed: #{e.class}: #{e.message}"
    nil
  end

  def judge(answer, key)
    if answer.is_a?(Integer)
      return GONE.key?(answer) ? missing(GONE[answer]) : unknown("MEGA answered #{answer}")
    end
    return unknown('MEGA answered without the file attributes') unless answer.is_a?(Hash) && answer['at']

    opens?(answer['at'], key) ? Result.new(state: :available) : missing('the key in the link does not open the file')
  end

  # MEGA's own derivation, from its web client: the 256-bit key in the link folded to a
  # 128-bit AES key by XORing its halves, then the attributes decrypted with AES-CBC under a
  # zero IV. The player reads only the first 32 bytes of the key, so a stray character on the
  # end of a pasted key is harmless -- three in this library have one, and their keys still
  # open their files -- and this reads it the same way rather than failing them.
  def opens?(attributes, key)
    bytes = decode(key).bytes
    return false if bytes.size < 32

    cipher = OpenSSL::Cipher.new('aes-128-cbc').tap do |aes|
      aes.decrypt
      aes.key = (0...16).map { |i| bytes[i] ^ bytes[i + 16] }.pack('C*')
      aes.iv = "\0" * 16
      aes.padding = 0
    end

    (cipher.update(decode(attributes)) + cipher.final).start_with?('MEGA{')
  rescue ArgumentError, OpenSSL::Cipher::CipherError
    false
  end

  # URL-safe base64 as MEGA writes it: no padding.
  def decode(text) = Base64.urlsafe_decode64(text + ('=' * ((4 - (text.length % 4)) % 4)))

  def missing(detail) = Result.new(state: :missing, detail: detail)
  def unknown(detail) = Result.new(state: :unknown, detail: detail)
end
