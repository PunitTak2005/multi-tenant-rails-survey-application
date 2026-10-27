# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_27_130000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "answers", force: :cascade do |t|
    t.bigint "submission_id", null: false
    t.bigint "question_id", null: false
    t.text "text_value"
    t.decimal "number_value", precision: 15, scale: 2
    t.bigint "selected_option_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["question_id"], name: "index_answers_on_question_id"
    t.index ["selected_option_id"], name: "index_answers_on_selected_option_id"
    t.index ["submission_id", "question_id"], name: "index_answers_on_submission_id_and_question_id"
    t.index ["submission_id"], name: "index_answers_on_submission_id"
  end

  create_table "customers", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "question_options", force: :cascade do |t|
    t.bigint "question_id", null: false
    t.string "label", null: false
    t.integer "position", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["question_id", "position"], name: "index_question_options_on_question_id_and_position"
    t.index ["question_id"], name: "index_question_options_on_question_id"
  end

  create_table "questions", force: :cascade do |t|
    t.bigint "survey_id", null: false
    t.text "question_text", null: false
    t.integer "question_type", default: 0, null: false
    t.integer "position", default: 1, null: false
    t.boolean "required", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["survey_id", "position"], name: "index_questions_on_survey_id_and_position"
    t.index ["survey_id"], name: "index_questions_on_survey_id"
  end

  create_table "submissions", force: :cascade do |t|
    t.bigint "survey_id", null: false
    t.datetime "submitted_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "respondent_token_digest"
    t.index ["submitted_at"], name: "index_submissions_on_submitted_at"
    t.index ["survey_id", "respondent_token_digest"], name: "index_submissions_on_survey_and_respondent_digest", unique: true, where: "(respondent_token_digest IS NOT NULL)"
    t.index ["survey_id", "submitted_at"], name: "index_submissions_on_survey_id_and_submitted_at"
    t.index ["survey_id"], name: "index_submissions_on_survey_id"
  end

  create_table "survey_daily_metrics", force: :cascade do |t|
    t.bigint "survey_id", null: false
    t.date "date", null: false
    t.integer "response_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_survey_daily_metrics_on_date"
    t.index ["survey_id", "date"], name: "index_survey_daily_metrics_on_survey_id_and_date", unique: true
    t.index ["survey_id"], name: "index_survey_daily_metrics_on_survey_id"
  end

  create_table "surveys", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.string "title", null: false
    t.text "description"
    t.integer "status", default: 0, null: false
    t.string "public_token", null: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "limit_one_response_per_device", default: false, null: false
    t.index ["customer_id", "created_at"], name: "index_surveys_on_customer_id_and_created_at"
    t.index ["customer_id", "status"], name: "index_surveys_on_customer_id_and_status"
    t.index ["customer_id"], name: "index_surveys_on_customer_id"
    t.index ["public_token"], name: "index_surveys_on_public_token", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_users_on_customer_id"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "answers", "question_options", column: "selected_option_id", on_delete: :nullify
  add_foreign_key "answers", "questions", on_delete: :cascade
  add_foreign_key "answers", "submissions", on_delete: :cascade
  add_foreign_key "question_options", "questions", on_delete: :cascade
  add_foreign_key "questions", "surveys", on_delete: :cascade
  add_foreign_key "submissions", "surveys", on_delete: :cascade
  add_foreign_key "survey_daily_metrics", "surveys", on_delete: :cascade
  add_foreign_key "surveys", "customers", on_delete: :cascade
  add_foreign_key "users", "customers", on_delete: :cascade
end
