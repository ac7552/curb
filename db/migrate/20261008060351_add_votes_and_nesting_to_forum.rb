class AddVotesAndNestingToForum < ActiveRecord::Migration[8.0]
  def change
    # Replies can answer other replies (nested, like Reddit).
    add_reference :forum_posts, :parent, foreign_key: { to_table: :forum_posts, on_delete: :cascade }

    # Each thread's and reply's score (upvotes minus downvotes), kept up to date as people vote.
    add_column :forum_threads, :score, :integer, null: false, default: 0
    add_column :forum_posts, :score, :integer, null: false, default: 0
    add_index :forum_threads, %i[make_key model_key score]

    # One vote per person per thread or reply: +1 or -1.
    create_table :forum_votes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :votable, polymorphic: true, null: false
      t.integer :value, null: false
      t.timestamps
    end
    add_index :forum_votes, %i[user_id votable_type votable_id], unique: true
  end
end
