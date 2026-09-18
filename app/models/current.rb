# frozen_string_literal: true

# Per-request state, reset between requests by Rails. Holds the things that would otherwise
# be read from the database several times in one request to give the same answer each time.
class Current < ActiveSupport::CurrentAttributes
  attribute :app_setting

  # The active imdb providers, in dial order. Every entry that names no provider of its own
  # asks for these while a page renders, and a channel page renders ~1,200 entries.
  attribute :active_imdb_sources
end
