class AddUpNextFractionToAppSettings < ActiveRecord::Migration[8.1]
  def change
    # How far through a film the up-next countdown appears. Was CREDITS_FRACTION, a
    # constant in player_progress_controller.js, so moving it meant a deploy.
    add_column :app_settings, :up_next_fraction, :float, default: 0.98, null: false
  end
end
