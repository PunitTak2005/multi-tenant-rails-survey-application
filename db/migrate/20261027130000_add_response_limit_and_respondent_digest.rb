# frozen_string_literal: true

class AddResponseLimitAndRespondentDigest < ActiveRecord::Migration[8.1]
  def change
    add_column :surveys, :limit_one_response_per_device, :boolean, default: false, null: false
    add_column :submissions, :respondent_token_digest, :string
    add_index :submissions, %i[survey_id respondent_token_digest],
              unique: true,
              where: "respondent_token_digest IS NOT NULL",
              name: "index_submissions_on_survey_and_respondent_digest"
  end
end
