class AddThemesToServiceBulletins < ActiveRecord::Migration[8.0]
  def change
    # Known failure themes found in the title ("timing-chain", "water-pump"), see BulletinTheme.
    add_column :service_bulletins, :themes, :string, array: true, null: false, default: []
    add_index :service_bulletins, :themes, using: :gin
  end
end
