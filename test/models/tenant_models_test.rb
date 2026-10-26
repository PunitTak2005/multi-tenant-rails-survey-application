require "test_helper"

class TenantModelsTest < ActiveSupport::TestCase
  setup do
    @customer = Customer.create!(name: "Test Customer")
  end

  test "customer requires name" do
    customer = Customer.new(name: nil)
    assert_not customer.valid?
    assert_includes customer.errors[:name], "can't be blank"
  end

  test "user email is normalized and validated" do
    user = @customer.users.create!(
      name: "John Doe",
      email: "  JOHN.DOE@Example.com  ",
      password: "ChangeMe123!"
    )
    assert_equal "john.doe@example.com", user.email
  end

  test "user email uniqueness is enforced" do
    @customer.users.create!(
      name: "Original User",
      email: "duplicate@example.com",
      password: "ChangeMe123!"
    )

    duplicate_user = @customer.users.build(
      name: "Duplicate User",
      email: "DUPLICATE@example.com",
      password: "ChangeMe123!"
    )
    assert_not duplicate_user.valid?
    assert_includes duplicate_user.errors[:email], "has already been taken"
  end

  test "survey generates public token automatically" do
    survey = @customer.surveys.create!(title: "Feedback Survey")
    assert survey.public_token.present?
    assert survey.draft?
  end

  test "survey publishable checks question requirements" do
    survey = @customer.surveys.create!(title: "Incomplete Survey")
    assert_not survey.publishable?
    assert_includes survey.errors[:base], "Survey must have at least one question to be published."

    # Add multiple choice without options
    mc = survey.questions.create!(
      question_text: "Favorite Color?",
      question_type: :multiple_choice,
      position: 1
    )
    assert_not survey.publishable?

    # Add option
    mc.question_options.create!(label: "Blue", position: 1)
    assert survey.publishable?
  end

  test "question option only allowed on multiple choice questions" do
    survey = @customer.surveys.create!(title: "Survey")
    text_q = survey.questions.create!(
      question_text: "What is your name?",
      question_type: :text,
      position: 1
    )

    opt = QuestionOption.new(question: text_q, label: "Invalid Option", position: 1)
    assert_not opt.valid?
    assert_includes opt.errors[:question], "must be multiple choice to have options"
  end

  test "answer validates type consistency" do
    survey = @customer.surveys.create!(title: "Survey")
    num_q = survey.questions.create!(
      question_text: "Your age?",
      question_type: :number,
      position: 1,
      required: true
    )

    submission = survey.submissions.create!(submitted_at: Time.current)

    # Invalid: text value on number question
    invalid_ans = Answer.new(
      submission: submission,
      question: num_q,
      text_value: "Thirty"
    )
    assert_not invalid_ans.valid?
    assert_includes invalid_ans.errors[:base], "Number questions cannot have text or option values"

    # Valid numeric answer
    valid_ans = Answer.new(
      submission: submission,
      question: num_q,
      number_value: 30
    )
    assert valid_ans.valid?
  end
end
