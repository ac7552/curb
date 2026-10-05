class CreateReports < ActiveRecord::Migration[8.0]
  def change
    create_table :reports do |t|
      t.references :user, null: false, foreign_key: true
      t.string :share_token, null: false, index: { unique: true }
      t.string :lookup_mode, null: false, default: "model"
      t.string :country, null: false
      t.string :vin
      t.string :plate
      t.string :make, null: false
      t.string :model, null: false
      t.integer :model_year, null: false
      t.string :engine
      t.string :fuel_type
      t.date :first_used_on
      t.integer :current_mileage, null: false
      t.decimal :asking_price, precision: 12, scale: 2, null: false
      t.integer :ownership_years, null: false, default: 3
      t.integer :miles_per_year, null: false
      t.string :addon_warranty, null: false, default: "none"
      t.integer :addon_years
      t.integer :addon_miles
      t.string :addon_coverage
      t.decimal :monthly_budget, precision: 10, scale: 2
      t.decimal :emergency_savings, precision: 12, scale: 2
      t.string :region, null: false
      t.string :shop_type, null: false, default: "independent"
      t.jsonb :live_data, null: false, default: {}
      t.jsonb :results, null: false, default: {}
      t.datetime :calculated_at
      t.timestamps
    end
    add_index :reports, %i[user_id created_at]
  end
end
