# frozen_string_literal: true

# Per-request state, reset between requests by Rails. Holds the things that would otherwise
# be read from the database several times in one request to give the same answer each time.
class Current < ActiveSupport::CurrentAttributes
  attribute :app_setting
end
