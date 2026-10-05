class CreateImportRuns < ActiveRecord::Migration[8.0]
  def change
    # One row per bulk file loaded, so a re-run skips files that are already in.
    create_table :import_runs do |t|
      t.string :source, null: false
      t.string :kind, null: false
      t.string :file_name, null: false
      t.bigint :file_size, null: false
      t.jsonb :counts, null: false, default: {}
      t.timestamps
    end
    add_index :import_runs, %i[source kind file_name file_size], unique: true
  end
end
