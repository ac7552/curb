# A bulletin that extends a warranty is a different kind of thing from one that tells a technician how
# to perform a repair: it is money the maker has already agreed to spend, and a used buyer can claim it.
# Both arrive in the same feed, so the distinction has to be stored to be queryable.
class AddProgramKindToServiceBulletins < ActiveRecord::Migration[8.0]
  def change
    add_column :service_bulletins, :program_kind, :string

    add_index :service_bulletins, [ :make_key, :model_key, :model_year, :program_kind ],
              where: "program_kind IS NOT NULL",
              name: "index_service_bulletins_on_car_and_program"
  end
end
