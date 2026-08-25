# Enforced. The main beneficiary is the embedded player: a third-party iframe can only use
# a feature if this page delegates it, so denying what the app never needs limits what an
# ad-heavy provider can ask the browser for.
#
# Set as a default header rather than through Rails' `permissions_policy` DSL, because that
# DSL still emits the superseded `Feature-Policy` header (see
# ActionDispatch::Constants::FEATURE_POLICY in actionpack 8.0) with the old
# `camera 'none'` syntax. Current browsers only honour `Permissions-Policy` with
# `camera=()` syntax, so the DSL would have bought nothing.
#
# Privacy Sandbox directives (browsing-topics, run-ad-auction, join-ad-interest-group,
# attribution-reporting, private-*) are deliberately absent: browsers that do not implement
# them log "Unrecognized feature" for each one, which is the same console noise the
# provider's own header already generates. Ours would double it without blocking anything.
DENIED_FEATURES = %w[
  camera microphone geolocation payment usb serial hid midi
  idle-detection display-capture accelerometer gyroscope magnetometer
  ambient-light-sensor keyboard-map web-share sync-xhr
].freeze

# What the player legitimately needs. Left open rather than pinned to a provider list: the
# `custom` Source passes arbitrary hosts through, so an allowlist would break playback for
# those entries. None of these is a privacy concern.
ALLOWED_FEATURES = %w[autoplay fullscreen encrypted-media picture-in-picture].freeze

PERMISSIONS_POLICY = (
  DENIED_FEATURES.map { |feature| "#{feature}=()" } +
  ALLOWED_FEATURES.map { |feature| "#{feature}=*" }
).join(", ")

Rails.application.config.action_dispatch.default_headers =
  Rails.application.config.action_dispatch.default_headers.merge(
    "Permissions-Policy" => PERMISSIONS_POLICY
  )
