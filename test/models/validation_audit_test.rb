require "test_helper"

class ValidationAuditTest < ActiveSupport::TestCase
  setup do
    @customer = Customer.create!(name: "Audit Customer")
    @survey = @customer.surveys.create!(title: "Audit Survey")
  end

  # --- Customer Validations ---
  test "Customer: rejects empty name" do
    cust = Customer.new(name: "")
    assert_not cust.valid?
    assert_includes cust.errors[:name], "can't be blank"

    cust.name = "   "
    assert_not cust.valid?
  end

  # --- User Validations ---
  test "User: rejects empty email" do
    user = @customer.users.build(name: "User", email: "", password: "password123")
    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  test "User: rejects invalid email formats" do
    ["invalid-email", "@no-user.com", "user@", "user @space.com"].each do |invalid_email|
      user = @customer.users.build(name: "User", email: invalid_email, password: "password123")
      assert_not user.valid?, "Expected #{invalid_email} to be invalid"
      assert_includes user.errors[:email], "is invalid"
    end
  end

  test "User: rejects duplicate email regardless of case" do
    @customer.users.create!(name: "First", email: "audit@test.com", password: "password123")
    dup = @customer.users.build(name: "Second", email: "AUDIT@TEST.COM", password: "password123")
    assert_not dup.valid?
    assert_includes dup.errors[:email], "has already been taken"
  end

  test "User: rejects empty and short passwords" do
    user = @customer.users.build(name: "User", email: "u@test.com", password: "")
    assert_not user.valid?

    user.password = "12345" # 5 chars < 6 minimum
    assert_not user.valid?
    assert_includes user.errors[:password], "is too short (minimum is 6 characters)"
  end

  # --- Survey Validations ---
  test "Survey: rejects empty title and missing customer" do
    s = Survey.new(title: "")
    assert_not s.valid?
    assert_includes s.errors[:title], "can't be blank"
    assert_includes s.errors[:customer], "must exist"
  end

  test "Survey: validates status values" do
    assert_raises(ArgumentError) do
      @survey.status = :archived # undefined status
    end
  end

  # --- Question Validations ---
  test "Question: rejects empty text and missing survey" do
    q = Question.new(question_text: "", position: 1)
    assert_not q.valid?
    assert_includes q.errors[:question_text], "can't be blank"
    assert_includes q.errors[:survey], "must exist"
  end

  test "Question: rejects invalid position numbers" do
    [0, -1, 1.5].each do |bad_pos|
      q = @survey.questions.build(question_text: "Text", position: bad_pos)
      assert_not q.valid?, "Expected position #{bad_pos} to be rejected"
    end
  end

  test "Question: rejects options on non-multiple-choice questions" do
    q_text = @survey.questions.create!(question_text: "Text Q", question_type: :text, position: 1)
    opt = QuestionOption.new(question: q_text, label: "Illegal Option", position: 1)
    assert_not opt.valid?
    assert_includes opt.errors[:question], "must be multiple choice to have options"
  end

  # --- QuestionOption Validations ---
  test "QuestionOption: rejects empty label and invalid position" do
    q_mc = @survey.questions.create!(question_text: "MC Q", question_type: :multiple_choice, position: 1)

    opt = q_mc.question_options.build(label: "", position: 1)
    assert_not opt.valid?
    assert_includes opt.errors[:label], "can't be blank"

    opt.label = "Valid"
    opt.position = -2
    assert_not opt.valid?
  end

  # --- Answer Validations ---
  test "Answer: enforces matching data types for question types" do
    q_text = @survey.questions.create!(question_text: "Text?", question_type: :text, position: 1, required: true)
    q_num = @survey.questions.create!(question_text: "Num?", question_type: :number, position: 2, required: true)
    q_mc = @survey.questions.create!(question_text: "MC?", question_type: :multiple_choice, position: 3, required: true)
    opt = q_mc.question_options.create!(label: "Opt A", position: 1)

    sub = @survey.submissions.create!(submitted_at: Time.current)

    # 1. Text question cannot accept number or option
    ans_text_bad = sub.answers.build(question: q_text, number_value: 42)
    assert_not ans_text_bad.valid?
    assert_includes ans_text_bad.errors[:base], "Text questions cannot have number or option values"

    ans_text_bad2 = sub.answers.build(question: q_text, selected_option: opt)
    assert_not ans_text_bad2.valid?
    assert_includes ans_text_bad2.errors[:base], "Text questions cannot have number or option values"

    # 2. Number question cannot accept text or option
    ans_num_bad = sub.answers.build(question: q_num, text_value: "invalid")
    assert_not ans_num_bad.valid?
    assert_includes ans_num_bad.errors[:base], "Number questions cannot have text or option values"

    # 3. Multiple choice question cannot accept text or number
    ans_mc_bad = sub.answers.build(question: q_mc, text_value: "bad")
    assert_not ans_mc_bad.valid?
    assert_includes ans_mc_bad.errors[:base], "Multiple choice questions cannot have text or number values"

    # 4. Multiple choice question rejects option from another question
    q_mc2 = @survey.questions.create!(question_text: "MC 2?", question_type: :multiple_choice, position: 4)
    foreign_opt = q_mc2.question_options.create!(label: "Foreign Opt", position: 1)

    ans_hijack = sub.answers.build(question: q_mc, selected_option: foreign_opt)
    assert_not ans_hijack.valid?
    assert_includes ans_hijack.errors[:selected_option_id], "must belong to this question"
  end

  test "Answer: numeric edge cases (0, negative, decimal, large number)" do
    q_num = @survey.questions.create!(question_text: "Num?", question_type: :number, position: 1)
    sub = @survey.submissions.create!(submitted_at: Time.current)

    # Zero
    ans_zero = sub.answers.create!(question: q_num, number_value: 0)
    assert ans_zero.persisted?
    assert_equal BigDecimal("0"), ans_zero.reload.number_value

    # Negative number
    ans_neg = sub.answers.create!(question: q_num, number_value: -15.75)
    assert ans_neg.persisted?
    assert_equal BigDecimal("-15.75"), ans_neg.reload.number_value

    # Large decimal number
    ans_large = sub.answers.create!(question: q_num, number_value: 999999999.99)
    assert ans_large.persisted?
    assert_equal BigDecimal("999999999.99"), ans_large.reload.number_value
  end
end
