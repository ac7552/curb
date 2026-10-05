class CreateModelPartProfiles < ActiveRecord::Migration[8.0]
  def up
    execute "SET LOCAL work_mem = '512MB'"
    create_view :model_part_profiles, materialized: true
    add_index :model_part_profiles, %i[make_key model_key engine_key build_year defect_category_id],
      unique: true, name: "index_model_part_profiles_on_group_and_part"
  end

  def down
    drop_view :model_part_profiles, materialized: true
  end
end
