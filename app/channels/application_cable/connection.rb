# frozen_string_literal: true

module ApplicationCable
  # The socket is opened by an already-signed-in page, so the identity is whatever Warden
  # put in the session -- the same account `current_user` returns everywhere else.
  #
  # Impersonation deliberately does not reach here: `env['warden'].user` is the real
  # account, so an admin viewing as someone else joins a party as themselves rather than
  # taking over that person's seat in the room.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      env['warden']&.user || reject_unauthorized_connection
    end
  end
end
