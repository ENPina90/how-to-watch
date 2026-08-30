class CreateAppSettings < ActiveRecord::Migration[8.0]
  def change
    # Site-wide switches an admin flips from the dashboard. One row, ever -- AppSetting
    # enforces that -- so a setting is a column here rather than a key/value pair, and
    # reading one is a column read instead of a lookup.
    create_table :app_settings do |t|
      # Who can reach the site without an account: 'secure' (nobody), 'moderate' (browse
      # only), 'open' (browse and watch). See AppSetting::ACCESS_MODES.
      t.string :access_mode, null: false, default: 'secure'

      t.timestamps
    end
  end
end
