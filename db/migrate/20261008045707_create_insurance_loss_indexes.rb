class CreateInsuranceLossIndexes < ActiveRecord::Migration[8.0]
  def change
    # How a model's insurance claims compare with the average vehicle (100 = average), for model years from..to:
    # injury, collision, theft (comprehensive) and property damage. Empty until there's data we're allowed to use
    # (HLDI's needs their written permission); a model with no row counts as average.
    create_table :insurance_loss_indexes do |t|
      t.string :make_key, null: false
      t.string :model_key, null: false
      t.integer :year_from, null: false
      t.integer :year_to, null: false
      t.integer :injury
      t.integer :collision
      t.integer :theft
      t.integer :property_damage
      t.string :source, null: false
      t.timestamps
    end
    add_index :insurance_loss_indexes, %i[make_key model_key year_from], unique: true
  end
end
