class CreateForum < ActiveRecord::Migration[8.0]
  def change
    # Our Garage: discussion threads in each model's room (make_key + model_key), with replies.
    create_table :forum_threads do |t|
      t.references :user, null: false, foreign_key: true
      t.string :make_key, null: false
      t.string :model_key, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.integer :forum_posts_count, null: false, default: 0
      t.datetime :last_posted_at, null: false
      t.datetime :hidden_at
      t.timestamps
    end
    add_index :forum_threads, %i[make_key model_key last_posted_at]

    create_table :forum_posts do |t|
      t.references :forum_thread, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.datetime :hidden_at
      t.timestamps
    end

    # Someone flagging a thread or reply for a moderator.
    create_table :forum_reports do |t|
      t.references :reporter, null: false, foreign_key: { to_table: :users }
      t.references :reportable, polymorphic: true, null: false
      t.string :reason, null: false
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :forum_reports, %i[reporter_id reportable_type reportable_id], unique: true

    # Banned people can still sign in and see their checks, but can't post.
    add_column :users, :banned_at, :datetime
  end
end
