class CreateSubmissions < ActiveRecord::Migration[8.0]
  def change
    create_table :submissions do |t|
      t.references :survey, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.datetime :submitted_at, null: false

      t.timestamps
    end

    add_index :submissions, [ :survey_id, :submitted_at ]
    add_index :submissions, :submitted_at
  end
end
