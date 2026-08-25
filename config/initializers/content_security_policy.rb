# REPORT-ONLY for now: violations are logged to the browser console, nothing is blocked.
#
# All 12 inline <script> blocks now carry a nonce, so `script_src` omitting :unsafe_inline
# no longer produces violations. What still stands between this and enforcement is
# `style_src :unsafe_inline` (101 inline style attributes across the views) -- that is a
# real weakening, since it is style-src's whole protection. Flipping
# `content_security_policy_report_only` to false is safe for scripts today; do it after
# watching the console stay quiet on the player pages, which are the ones with third-party
# frames.
#
# spec/requests/content_security_policy_spec.rb fails if a new inline <script> lands
# without a nonce.
#
# Sources below were taken from what the app actually loads, not guessed:
#   scripts  importmap pins (jspm, unpkg, cdnjs) + jsdelivr in the mobile layout
#   styles   Google Fonts, jsdelivr (mobile layout), and 101 inline style attributes
#   images   TMDB and Cloudinary, plus arbitrary `pic` URLs on entries -> https:
#   frames   the Source provider hosts; the `custom` provider passes arbitrary hosts
#            through, which is why this is https: rather than an allowlist
Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.object_src  :none
  policy.base_uri    :self
  policy.form_action :self

  policy.script_src  :self,
                     "https://ga.jspm.io",
                     "https://unpkg.com",
                     "https://cdnjs.cloudflare.com",
                     "https://cdn.jsdelivr.net"

  # 101 inline style attributes across the views; :unsafe_inline is realistic here.
  policy.style_src   :self, :unsafe_inline,
                     "https://fonts.googleapis.com",
                     "https://cdn.jsdelivr.net"

  policy.font_src    :self, :data, "https://fonts.gstatic.com"
  policy.img_src     :self, :data, :https
  policy.connect_src :self, "https://api.themoviedb.org"
  policy.media_src   :self, :https
  policy.frame_src   :self, :https
end

# One fresh nonce per response. The Rails scaffold ties this to `request.session.id`,
# which is the right call only when responses are cached -- a cached page carries a stale
# nonce, so it has to stay stable for the session. Nothing here is page- or fragment-cached,
# and a session-derived nonce is both reused across every response for that session and
# empty before a session exists (a signed-out visitor would get `nonce=""`, which matches
# nothing once this is enforced).
Rails.application.config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
Rails.application.config.content_security_policy_nonce_directives = %w[script-src]

Rails.application.config.content_security_policy_report_only = true
