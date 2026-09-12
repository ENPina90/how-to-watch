# frozen_string_literal: true

# The up-next card was timed as a share of the runtime. It is timed as a lead before the
# end instead: "fifteen seconds before it finishes" is what anybody actually means by it,
# and the percentage was two and a half minutes of a feature and twenty seconds of an
# episode -- the dashboard already carried a paragraph translating the one into the other,
# which is the tell.
#
# The old value is not carried across, because it cannot be: 0.98 is not a number of
# seconds until you say how long the film is. Everybody gets the new default.
#
# The floor that used to live in a validation (never earlier than the completion mark) is
# now applied where the mark is worked out, in AppSetting#up_next_mark_for and in
# player_progress_controller. It has to be: fifteen seconds before the end of a two-minute
# clip is well before that clip counts as watched, and no validation on a setting that
# knows nothing about runtimes could have caught it.
class ReplaceUpNextFractionWithLeadSeconds < ActiveRecord::Migration[8.1]
  def up
    add_column :app_settings, :up_next_lead_seconds, :integer, default: 15, null: false
    remove_column :app_settings, :up_next_fraction
  end

  def down
    add_column :app_settings, :up_next_fraction, :float, default: 0.98, null: false
    remove_column :app_settings, :up_next_lead_seconds
  end
end
