class AddErrorToFailedEntry < ActiveRecord::Migration[7.0]
  def change
    add_column :failed_entries, :error, :string
  end
end
