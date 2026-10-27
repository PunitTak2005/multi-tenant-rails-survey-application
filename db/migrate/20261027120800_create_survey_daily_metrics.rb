# frozen_string_literal: true

class CreateSurveyDailyMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :survey_daily_metrics do |t|
      t.references :survey, null: false, foreign_key: { on_delete: :cascade }
      t.date :date, null: false
      t.integer :response_count, null: false, default: 0

      t.timestamps
    end

    add_index :survey_daily_metrics, [ :survey_id, :date ], unique: true
    add_index :survey_daily_metrics, :date
  end
end
