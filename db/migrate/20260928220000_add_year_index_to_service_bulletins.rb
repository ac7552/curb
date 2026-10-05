class AddYearIndexToServiceBulletins < ActiveRecord::Migration[8.0]
  def change
    # For comparing one car's bulletins with every other car from the same model year.
    add_index :service_bulletins, %i[model_year category_slug make_key model_key]
  end
end
