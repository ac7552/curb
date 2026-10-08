class CreateFeatureFlags < ActiveRecord::Migration[8.0]
  def change
    # A switch an admin has flipped. Switches nobody has touched fall back to their default in Feature.
    create_table :feature_flags do |t|
      t.string :key, null: false, index: { unique: true }
      t.boolean :enabled, null: false
      t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
  end
end
