# frozen_string_literal: true

module Users
  class RegistrationsController < Devise::RegistrationsController
    protected

    # The email-and-password form lives on the profile page, so saving it belongs back
    # there. Devise's default drops you at the site root, which reads as having been
    # logged out.
    def after_update_path_for(_resource)
      profile_path
    end
  end
end
