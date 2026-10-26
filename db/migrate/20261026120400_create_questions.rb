class CreateQuestions < ActiveRecord::Migration[8.0]
  def change
    create_table :questions do |t|
      t.references :survey, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.text :question_text, null: false
      t.integer :question_type, null: false, default: 0
      t.integer :position, null: false, default: 1
      t.boolean :required, null: false, default: false

      t.timestamps
    end

    add_index :questions, [ :survey_id, :position ]
  end
end
