# frozen_string_literal: true

module PlayerHelper
  # The origins a framed player will reach for, so the page can open the connections while
  # it is still parsing rather than after the frame has loaded.
  #
  # Two of them, and they are worth different amounts. The front door is where the embed
  # URL points, and warming it gains little -- the iframe is a few hundred bytes further
  # down the same document, so its own connection opens at nearly the same moment. The
  # provider's inner origins are the real saving: the browser cannot discover those until
  # the first frame has loaded and parsed, so a DNS lookup, a TCP handshake and a TLS
  # negotiation all sit on the critical path that a preconnect takes off it.
  #
  # Returns [] for anything we cannot place -- a blank URL, or one that will not parse --
  # rather than emitting a link to nowhere.
  def player_preconnect_origins(url, source)
    ([front_door_origin(url)] + Array(source&.preconnect_origins)).compact.uniq
  end

  private

  def front_door_origin(url)
    return nil if url.blank?

    uri = URI.parse(url)
    return nil unless uri.scheme.in?(%w[http https]) && uri.host.present?

    "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.default_port == uri.port}"
  rescue URI::InvalidURIError
    nil
  end
end
