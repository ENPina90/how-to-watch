# frozen_string_literal: true

# How long before the end of its entries a channel considers them over, in seconds.
#
# The companion to skip_intro_seconds. A file runs to the end of its credits, and on a
# channel of episodes that is a minute or two of the same titles every time -- which is
# exactly the stretch Auto Next is for skipping. Everything that asks "is this over?" moves
# to the earlier point together: the mark where the entry counts as watched, the point past
# which it starts again rather than resuming, and the up-next card, so its countdown runs
# out where the programme does rather than where the file does.
#
# Nullable, and null is today's behaviour on every channel: the entry ends where the file
# ends, and the site-wide up-next lead alone decides when the card comes up.
class AddSkipCreditsSecondsToLists < ActiveRecord::Migration[8.1]
  def change
    add_column :lists, :skip_credits_seconds, :integer
  end
end
