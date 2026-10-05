class CreateReferenceTables < ActiveRecord::Migration[8.0]
  def change
    create_table :defect_categories do |t|
      t.string :name, null: false
      t.string :slug, null: false, index: { unique: true }
      t.string :warranty_type, null: false, default: "none"
      t.decimal :labor_hours, precision: 5, scale: 2, null: false, default: 0
      t.decimal :parts_cost_usd, precision: 10, scale: 2, null: false, default: 0
      t.boolean :wear_item, null: false, default: false
      t.string :keywords, array: true, null: false, default: []
      t.text :description
      t.timestamps
    end

    create_table :warranty_terms do |t|
      t.string :country, null: false
      t.string :make_key, null: false
      t.string :coverage_type, null: false
      t.integer :years, null: false
      t.integer :miles
      t.boolean :transferable, null: false, default: true
      t.integer :model_year_from
      t.integer :model_year_to
      t.string :notes
      t.timestamps
    end
    add_index :warranty_terms, %i[country make_key coverage_type]

    create_table :service_items do |t|
      t.string :make_key
      t.string :model_key
      t.string :name, null: false
      t.integer :interval_miles
      t.integer :interval_months
      t.decimal :labor_hours, precision: 5, scale: 2, null: false, default: 0
      t.decimal :parts_cost_usd, precision: 10, scale: 2, null: false, default: 0
      t.boolean :wear_item, null: false, default: false
      t.timestamps
    end
    add_index :service_items, %i[make_key model_key]

    create_table :labor_rates do |t|
      t.string :country, null: false
      t.string :region, null: false
      t.string :shop_type, null: false
      t.decimal :hourly_rate, precision: 8, scale: 2, null: false
      t.timestamps
    end
    add_index :labor_rates, %i[country region shop_type], unique: true

    create_table :recalls do |t|
      t.string :campaign_number, null: false, index: { unique: true }
      t.string :country, null: false, default: "US"
      t.string :make_key, null: false
      t.string :model_key, null: false
      t.integer :year_from, null: false
      t.integer :year_to, null: false
      t.string :component
      t.text :summary
      t.text :remedy
      t.date :reported_on
      t.references :defect_category, foreign_key: true
      t.timestamps
    end
    add_index :recalls, %i[make_key model_key]
  end
end
