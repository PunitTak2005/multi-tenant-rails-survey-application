require "test_helper"

class SubmitSurveyTest < ActiveSupport::TestCase
  setup do
    @customer = Customer.create!(name: "Test Customer")
    @survey = @customer.surveys.create!(
      title: "Public Test Survey",
      status: :published,
      published_at: Time.current
    )

    @q_text = @survey.questions.create!(
      question_text: "Comments",
      question_type: :text,
      position: 1,
      required: false
    )

    @q_num = @survey.questions.create!(
      question_text: "Rating",
      question_type: :number,
      position: 2,
      required: true
    )

    @q_mc = @survey.questions.create!(
      question_text: "Choice",
      question_type: :multiple_choice,
      position: 3,
      required: true
    )
    @opt1 = @q_mc.question_options.create!(label: "Option 1", position: 1)
    @opt2 = @q_mc.question_options.create!(label: "Option 2", position: 2)

    # Another question on another survey for option hijacking test
    @other_survey = @customer.surveys.create!(title: "Other Survey", status: :published)
    @other_q = @other_survey.questions.create!(question_text: "Other Q", question_type: :multiple_choice, position: 1)
    @other_opt = @other_q.question_options.create!(label: "Alien Option", position: 1)
  end

  test "successful survey submission creates submission and answers" do
    params = {
      @q_text.id.to_s => "Great service!",
      @q_num.id.to_s => "9.5",
      @q_mc.id.to_s => @opt1.id.to_s
    }

    assert_difference -> { @survey.submissions.count } => 1, -> { Answer.count } => 3 do
      result = SubmitSurvey.new(@survey, params).call
      assert result.success?
      assert_not_nil result.submission
      assert_equal 0, result.errors.size
    end

    sub = @survey.submissions.last
    text_ans = sub.answers.find_by(question: @q_text)
    num_ans = sub.answers.find_by(question: @q_num)
    mc_ans = sub.answers.find_by(question: @q_mc)

    assert_equal "Great service!", text_ans.text_value
    assert_equal BigDecimal("9.5"), num_ans.number_value
    assert_equal @opt1, mc_ans.selected_option
  end

  test "enforces required questions" do
    params = {
      @q_text.id.to_s => "Only comments provided"
      # missing required number and multiple choice
    }

    assert_no_difference [ -> { Submission.count }, -> { Answer.count } ] do
      result = SubmitSurvey.new(@survey, params).call
      assert_not result.success?
      assert result.errors.any? { |e| e.include?("required") }
    end
  end

  test "rejects non-numeric answers for number question" do
    params = {
      @q_num.id.to_s => "not-a-number",
      @q_mc.id.to_s => @opt1.id.to_s
    }

    assert_no_difference [ -> { Submission.count }, -> { Answer.count } ] do
      result = SubmitSurvey.new(@survey, params).call
      assert_not result.success?
      assert result.errors.any? { |e| e.include?("valid number") }
    end
  end

  test "rejects option from a different question" do
    params = {
      @q_num.id.to_s => "10",
      @q_mc.id.to_s => @other_opt.id.to_s # Option belongs to @other_q!
    }

    assert_no_difference [ -> { Submission.count }, -> { Answer.count } ] do
      result = SubmitSurvey.new(@survey, params).call
      assert_not result.success?
      assert result.errors.any? { |e| e.include?("invalid") }
    end
  end

  test "transaction ensures all-or-nothing rollback on error" do
    # Valid text, valid number, but invalid option
    params = {
      @q_text.id.to_s => "Partial text",
      @q_num.id.to_s => "100",
      @q_mc.id.to_s => 999_999.to_s # nonexistent option
    }

    assert_no_difference [ -> { Submission.count }, -> { Answer.count } ] do
      result = SubmitSurvey.new(@survey, params).call
      assert_not result.success?
    end
  end

  test "refuses submission to draft survey" do
    draft_survey = @customer.surveys.create!(title: "Draft Survey", status: :draft)
    result = SubmitSurvey.new(draft_survey, {}).call
    assert_not result.success?
    assert_includes result.errors, "This survey is not published."
  end
end
