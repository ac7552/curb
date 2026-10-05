class CreateInspectionTables < ActiveRecord::Migration[8.0]
  def change
    create_table :vehicles do |t|
      t.string :source, null: false
      t.string :external_id, null: false
      t.string :country, null: false
      t.string :make, null: false
      t.string :model, null: false
      t.string :make_key, null: false
      t.string :model_key, null: false
      t.string :engine_key
      t.string :fuel_type
      t.integer :engine_cc
      t.integer :model_year
      t.date :first_used_on
      t.string :vin
      t.string :plate
      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :vehicles, %i[source external_id], unique: true
    add_index :vehicles, %i[make_key model_key engine_key]

    create_table :inspections do |t|
      t.references :vehicle, null: false, foreign_key: true
      t.string :source, null: false
      t.string :external_id, null: false
      t.date :inspected_on, null: false
      t.integer :mileage
      t.string :result, null: false
      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :inspections, %i[source external_id], unique: true

    # One row per unique defect wording; categorized once, reused for every defect that uses it.
    create_table :defect_phrases do |t|
      t.string :source, null: false
      t.string :external_id
      t.text :text, null: false
      t.references :defect_category, foreign_key: true
      t.string :categorized_by
      t.datetime :categorized_at
      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :defect_phrases, %i[source external_id], unique: true
    add_index :defect_phrases, :categorized_at

    create_table :defects do |t|
      t.references :inspection, null: false, foreign_key: true
      t.references :defect_phrase, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :severity
    end
  end
end
