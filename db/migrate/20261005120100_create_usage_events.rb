class CreateUsageEvents < ActiveRecord::Migration[8.0]
  def change
    # One row each time someone uses something a plan limits (a check today; deep checks and questions later),
    # so limits are counted from what happened rather than from a counter that can drift.
    create_table :usage_events do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.references :report, foreign_key: { on_delete: :nullify }
      t.datetime :created_at, null: false
    end
    add_index :usage_events, %i[user_id kind created_at]
  end
end
