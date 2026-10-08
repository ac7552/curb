class AddAdminToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :admin, :boolean, null: false, default: false
    # The site owner. More admins: bin/rails "curb:admin:grant[email]".
    execute "UPDATE users SET admin = TRUE WHERE email_address = 'aaron.campbell2590@gmail.com'"
  end

  def down
    remove_column :users, :admin
  end
end
