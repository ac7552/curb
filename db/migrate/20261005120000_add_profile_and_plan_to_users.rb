class AddProfileAndPlanToUsers < ActiveRecord::Migration[8.0]
  def change
    change_table :users, bulk: true do |t|
      t.string :first_name, null: false, default: ""
      t.string :last_name, null: false, default: ""
      t.string :country
      t.string :postal_code
      t.string :car_types, array: true, null: false, default: []

      # Billing: the plan this person is on and their Stripe records. Stripe is the source of truth; these are
      # kept in step by its webhooks so pages never wait on Stripe.
      t.string :plan, null: false, default: "free"
      t.string :stripe_customer_id
      t.string :stripe_subscription_id
      t.string :subscription_status
      t.datetime :plan_renews_at
    end
    add_index :users, :stripe_customer_id, unique: true
  end
end
