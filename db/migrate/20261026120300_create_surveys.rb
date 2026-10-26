class CreateSurveys < ActiveRecord::Migration[8.0]
  def change
    create_table :surveys do |t|
      t.references :customer, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :title, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.string :public_token, null: false
      t.datetime :published_at

      t.timestamps
    end

    add_index :surveys, :public_token, unique: true
    add_index :surveys, [ :customer_id, :status ]
    add_index :surveys, [ :customer_id, :created_at ]
  end
end
