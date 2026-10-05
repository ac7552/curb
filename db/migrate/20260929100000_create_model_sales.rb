class CreateModelSales < ActiveRecord::Migration[8.0]
  def change
    # New cars sold in the US per calendar year, so owner complaints can be counted per car sold.
    create_table :model_sales do |t|
      t.string :make_key, null: false
      t.string :model_key, null: false
      t.integer :year, null: false
      t.integer :units, null: false
      t.string :source, null: false
      t.string :source_url
      t.timestamps
    end
    add_index :model_sales, %i[make_key model_key year], unique: true
  end
end
