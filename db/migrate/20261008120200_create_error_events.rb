class CreateErrorEvents < ActiveRecord::Migration[8.0]
  def change
    # Crashes the app hit, one row per kind of crash (same error class, same place in our code), counted.
    create_table :error_events do |t|
      t.string :fingerprint, null: false, index: { unique: true }
      t.string :error_class, null: false
      t.text :message
      t.text :backtrace
      t.string :source
      t.string :path
      t.string :request_id
      t.references :user, foreign_key: { on_delete: :nullify }
      t.integer :occurrences, null: false, default: 1
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false, index: true
      t.datetime :resolved_at
      t.timestamps
    end
  end
end
