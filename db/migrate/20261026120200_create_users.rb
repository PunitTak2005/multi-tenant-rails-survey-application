class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.references :customer, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :name, null: false

      t.timestamps
    end

    add_index :users, :email, unique: true
  end
end
