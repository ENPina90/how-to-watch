# frozen_string_literal: true

# How far into its entries a channel opens them, in seconds.
#
# A channel of cartoons that all open on the same ninety seconds of titles knows something
# about where its programmes begin that no viewer's setting can: "Start part-way in" is a
# random window chosen by the person, and this is a fixed point chosen by the channel.
#
# Nullable, and null is not zero. Null is the channel having no opinion, so the viewer's own
# setting stands exactly as it did before this column existed -- which is every channel on
# the day this deploys. Zero is the channel saying "from the very start, always", which is
# an answer, and overrides the viewer the same way ninety does.
class AddSkipIntroSecondsToLists < ActiveRecord::Migration[8.1]
  def change
    add_column :lists, :skip_intro_seconds, :integer
  end
end
