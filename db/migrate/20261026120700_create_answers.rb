class CreateAnswers < ActiveRecord::Migration[8.0]
  def change
    create_table :answers do |t|
      t.references :submission, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :question, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.text :text_value
      t.decimal :number_value, precision: 15, scale: 2
      t.references :selected_option, foreign_key: { to_table: :question_options, on_delete: :nullify }, index: true

      t.timestamps
    end

    add_index :answers, [ :submission_id, :question_id ]
  end
end
