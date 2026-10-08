class CreateGarage < ActiveRecord::Migration[8.0]
  def change
    # Cars people own. Private to their owner; the photos (Active Storage, in walk-around order) make the 360° spin.
    create_table :garage_cars do |t|
      t.references :user, null: false, foreign_key: true
      t.string :make, null: false
      t.string :model, null: false
      t.integer :model_year, null: false
      t.string :nickname
      t.timestamps
    end

    # Products an owner is thinking of adding, from a link they pasted.
    create_table :garage_accessories do |t|
      t.references :garage_car, null: false, foreign_key: true
      t.string :url, null: false
      t.string :title, null: false
      t.string :price
      t.boolean :remove_background, null: false, default: false
      t.timestamps
    end

    # Where an accessory sits on one photo of the spin: centre (x, y) and width as fractions of the photo, and a turn.
    create_table :accessory_placements do |t|
      t.references :garage_accessory, null: false, foreign_key: true
      t.references :photo, null: false, foreign_key: { to_table: :active_storage_attachments, on_delete: :cascade }
      t.decimal :x, precision: 6, scale: 5, null: false
      t.decimal :y, precision: 6, scale: 5, null: false
      t.decimal :width, precision: 6, scale: 5, null: false
      t.decimal :rotation, precision: 6, scale: 2, null: false, default: 0
      t.timestamps
    end
    add_index :accessory_placements, %i[garage_accessory_id photo_id], unique: true
  end
end
