# Lets an admin browse the app as another user, to check what a non-admin actually sees.
#
# `current_user` is what the whole app reads for both identity *and* permission
# (`can_edit_list?`, `admin?`, the per-user tracking tables), so swapping it here is what
# makes the session behave like that other user everywhere, without a parallel "pretend"
# code path that could drift from the real one.
#
# The account that actually signed in stays in `true_user`; it is the only thing allowed
# to start an impersonation, and the only place the admin flag is read for that decision.
# Nothing else in the app should call `true_user` -- if it does, that page is showing the
# admin something a non-admin session would not show, which defeats the point.
module Impersonation
  extend ActiveSupport::Concern

  IMPERSONATION_KEY = :impersonated_user_id

  included do
    helper_method :true_user, :impersonating?, :impersonatable_users
  end

  # Devise's own `current_user` is exactly this call, memoized. Repeating it rather than
  # aliasing the original is deliberate: the alias would resolve back to the override
  # below, since including this module puts it ahead of Devise in the ancestor chain.
  def true_user
    @true_user ||= warden&.authenticate(scope: :user)
  end

  def current_user
    impersonated_user || true_user
  end

  def impersonating?
    impersonated_user.present?
  end

  # Everyone an admin can switch to, non-admins first since those are the sessions worth
  # checking. Ordered by admin so the list stays stable between renders.
  def impersonatable_users
    return User.none unless true_user&.admin?

    @impersonatable_users ||= User.where.not(id: true_user.id).order(:admin, :username, :email).to_a
  end

  private

  def impersonated_user
    return @impersonated_user if defined?(@impersonated_user)

    @impersonated_user = resolve_impersonated_user
  end

  def resolve_impersonated_user
    id = session[IMPERSONATION_KEY]
    return nil if id.blank?

    # Both of these can go stale mid-session: the admin flag can be revoked, and the
    # impersonated account can be deleted. Either way, drop back to the real account
    # rather than leaving the session pointing at nothing.
    unless true_user&.admin?
      session.delete(IMPERSONATION_KEY)
      return nil
    end

    User.find_by(id: id).tap { |user| session.delete(IMPERSONATION_KEY) if user.nil? }
  end
end
