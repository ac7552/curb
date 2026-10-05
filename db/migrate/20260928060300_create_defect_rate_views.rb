class CreateDefectRateViews < ActiveRecord::Migration[8.0]
  def change
    create_view :inspection_cells, materialized: true
    add_index :inspection_cells, %i[make_key model_key engine_key age_years mileage_band],
      unique: true, name: "index_inspection_cells_on_cell"

    create_view :defect_rates, materialized: true
    add_index :defect_rates, %i[make_key model_key engine_key age_years mileage_band defect_category_id],
      unique: true, name: "index_defect_rates_on_cell_and_category"

    create_view :defect_baselines, materialized: true
    add_index :defect_baselines, %i[defect_category_id age_years mileage_band],
      unique: true, name: "index_defect_baselines_on_category_and_band"
  end
end
