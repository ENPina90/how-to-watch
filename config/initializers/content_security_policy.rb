# REPORT-ONLY for now: violations are logged to the browser console, nothing is blocked.
#
# It cannot be enforced as written because 12 view files carry inline <script> blocks, and
# `script_src` here deliberately omits :unsafe_inline so those show up as violations. The
# path to enforcing it is to move those blocks into Stimulus controllers (or give them
# nonces via `javascript_tag nonce: true`), watch the console go quiet, then flip
# `content_security_policy_report_only` to false.
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

# Nonces are generated for any tag that opts in with `nonce: true`; nothing does yet.
Rails.application.config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
Rails.application.config.content_security_policy_nonce_directives = %w[script-src]

Rails.application.config.content_security_policy_report_only = true
