class CreateNhtsaTables < ActiveRecord::Migration[8.0]
  def change
    # NHTSA owner complaints, counted per car and part. Individual complaints (with owners' names,
    # cities and stories) are never stored.
    create_table :complaint_counts do |t|
      t.string :make_key, null: false
      t.string :model_key, null: false
      t.integer :model_year, null: false
      t.string :category_slug, null: false
      t.integer :complaints, null: false, default: 0
      t.integer :towed, null: false, default: 0
      t.integer :crashes, null: false, default: 0
      t.integer :fires, null: false, default: 0
      t.integer :with_miles, null: false, default: 0
      t.bigint :miles_total, null: false, default: 0
      t.timestamps
    end
    add_index :complaint_counts, %i[make_key model_key model_year category_slug], unique: true, name: "index_complaint_counts_on_car_and_part"
    add_index :complaint_counts, %i[category_slug model_year]

    # Technical service bulletins: fixes makers sent dealers for known problems. One row per car it covers.
    create_table :service_bulletins do |t|
      t.string :document_id, null: false
      t.string :make_key, null: false
      t.string :model_key, null: false
      t.integer :model_year, null: false
      t.string :title, null: false
      t.string :category_slug
      t.timestamps
    end
    add_index :service_bulletins, %i[make_key model_key model_year document_id], unique: true, name: "index_service_bulletins_on_car_and_document"
  end
end
