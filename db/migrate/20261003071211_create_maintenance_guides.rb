class CreateMaintenanceGuides < ActiveRecord::Migration[8.0]
  def change
    # One maker's maintenance guide for one car, read once (bin/rails curb:guides:prefill) and kept for
    # everyone who checks that car. Only "ok" rows are trusted; "needs_review" waits for a person.
    create_table :maintenance_guides do |t|
      t.string :make_key, null: false
      t.string :model_key, null: false
      t.integer :model_year, null: false
      t.string :make, null: false
      t.string :model, null: false
      t.string :status, null: false
      t.string :url, null: false
      t.string :title, null: false
      t.jsonb :rows, null: false, default: []
      t.jsonb :problems, null: false, default: []
      t.string :read_with
      t.datetime :read_at
      t.timestamps
    end
    add_index :maintenance_guides, %i[make_key model_key model_year], unique: true
  end
end
