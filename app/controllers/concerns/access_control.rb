# frozen_string_literal: true

# Who gets in without an account, per AppSetting#access_mode.
#
# The permitted actions are listed here rather than declared in each controller so that the
# whole answer to "what can a stranger reach" is one table you can read top to bottom. Two
# rules hold it down whatever the table says:
#
#   * only GETs are ever allowed through, so no guest can write even if an action is listed
#     by mistake;
#   * anything not listed falls through to Devise, so a new controller is closed until
#     someone decides otherwise.
module AccessControl
  extend ActiveSupport::Concern

  # Browsing: the channel index, a channel's own page, the pieces of it that load on their
  # own, and search. Everything here is a read of something already public.
  # The vote ballot is not here: VotesController skips this check outright, because a room
  # scanning a QR code is a different question from who may browse the site.
  BROWSE = {
    'lists' => %w[index show search entry_index nested_entries],
    'entries' => %w[fetch_posters]
  }.freeze

  # Watching, on top of browsing: the player itself, and the two ways in -- an entry, and a
  # channel's "play what's next". Recording where you got to still needs an account; those
  # are writes, and writes never come through here.
  WATCH = {
    'entries' => %w[watch show],
    'pages' => %w[watch_now],
    'lists' => %w[watch_current]
  }.freeze

  GUEST_ACTIONS = {
    'secure' => {},
    'moderate' => BROWSE,
    'open' => BROWSE.merge(WATCH) { |_controller, browse, watch| (browse + watch).uniq }
  }.freeze

  included do
    before_action :authenticate_user_unless_guest_allowed!, except: [:health]
  end

  # A private channel is not part of what an access mode opens up. What a *signed-in* user
  # may see of someone else's private channel is an older question than this feature and is
  # left exactly as it was; a stranger with the URL is the case the modes must not create.
  def refuse_guest_on_private!(list)
    return if user_signed_in?
    return unless list&.private?

    redirect_to new_user_session_path, alert: 'That channel is private.'
  end

  private

  def authenticate_user_unless_guest_allowed!
    return if user_signed_in?
    return if guest_allowed?

    authenticate_user!
  end

  def guest_allowed?
    return false unless request.get?

    GUEST_ACTIONS.fetch(AppSetting.access_mode, {})
                 .fetch(controller_name, [])
                 .include?(action_name)
  end
end
