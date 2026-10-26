import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["questionsContainer", "questionTemplate", "optionsContainer", "optionTemplate", "questionTypeSelect"]

  connect() {
    this.updateAllOptionVisibilities()
  }

  addQuestion(event) {
    event.preventDefault()
    const content = this.questionTemplateTarget.innerHTML.replace(/NEW_QUESTION_RECORD/g, new Date().getTime())
    this.questionsContainerTarget.insertAdjacentHTML("beforeend", content)
    this.updateAllOptionVisibilities()
  }

  removeQuestion(event) {
    event.preventDefault()
    const card = event.target.closest(".builder-question-card")
    const destroyInput = card.querySelector("input[name*='[_destroy]']")
    if (destroyInput) {
      destroyInput.value = "1"
      card.style.display = "none"
    } else {
      card.remove()
    }
  }

  addOption(event) {
    event.preventDefault()
    const optionsContainer = event.target.closest(".builder-options-section").querySelector(".builder-options-container")
    const questionIndex = optionsContainer.dataset.questionIndex
    const content = this.optionTemplateTarget.innerHTML
      .replace(/QUESTION_INDEX/g, questionIndex)
      .replace(/NEW_OPTION_RECORD/g, new Date().getTime())
    optionsContainer.insertAdjacentHTML("beforeend", content)
  }

  removeOption(event) {
    event.preventDefault()
    const optionRow = event.target.closest(".builder-option-row")
    const destroyInput = optionRow.querySelector("input[name*='[_destroy]']")
    if (destroyInput) {
      destroyInput.value = "1"
      optionRow.style.display = "none"
    } else {
      optionRow.remove()
    }
  }

  handleTypeChange(event) {
    const select = event.target
    const card = select.closest(".builder-question-card")
    const optionsSection = card.querySelector(".builder-options-section")
    if (select.value === "multiple_choice") {
      optionsSection.style.display = "block"
    } else {
      optionsSection.style.display = "none"
    }
  }

  updateAllOptionVisibilities() {
    this.element.querySelectorAll(".builder-question-card").forEach(card => {
      const select = card.querySelector("select[name*='[question_type]']")
      const optionsSection = card.querySelector(".builder-options-section")
      if (select && optionsSection) {
        if (select.value === "multiple_choice") {
          optionsSection.style.display = "block"
        } else {
          optionsSection.style.display = "none"
        }
      }
    })
  }
}
