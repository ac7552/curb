class AddBlurbToDefectCategories < ActiveRecord::Migration[8.0]
  def change
    # One plain sentence on what the part does, for buyers who aren't car people.
    add_column :defect_categories, :blurb, :string
  end
end
