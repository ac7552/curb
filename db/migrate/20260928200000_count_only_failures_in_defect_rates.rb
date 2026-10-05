# "Chance it breaks" counts MOT failures only; advisories are wear notes that often never need work.
# defect_baselines reads defect_rates, so it is dropped and rebuilt around the change.
class CountOnlyFailuresInDefectRates < ActiveRecord::Migration[8.0]
  def up
    execute "SET LOCAL work_mem = '512MB'"
    drop_view :defect_baselines, materialized: true
    drop_view :defect_rates, materialized: true
    create_view :defect_rates, version: 2, materialized: true
    add_index :defect_rates, %i[make_key model_key engine_key age_years mileage_band defect_category_id],
      unique: true, name: "index_defect_rates_on_cell_and_category"
    create_view :defect_baselines, version: 1, materialized: true
    add_index :defect_baselines, %i[defect_category_id age_years mileage_band],
      unique: true, name: "index_defect_baselines_on_category_and_band"
  end

  def down
    drop_view :defect_baselines, materialized: true
    drop_view :defect_rates, materialized: true
    create_view :defect_rates, version: 1, materialized: true
    add_index :defect_rates, %i[make_key model_key engine_key age_years mileage_band defect_category_id],
      unique: true, name: "index_defect_rates_on_cell_and_category"
    create_view :defect_baselines, version: 1, materialized: true
    add_index :defect_baselines, %i[defect_category_id age_years mileage_band],
      unique: true, name: "index_defect_baselines_on_category_and_band"
  end
end
