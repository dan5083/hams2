// app/javascript/controllers/operation_text_inputs_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textContainer", "input"]
  static values = {
    worksOrderId: String,
    operationPosition: Number
  }

  connect() {
    // Auto-focus first empty input when component loads
    this.focusFirstEmptyInput()
  }

  saveInput(event) {
    const input = event.target
    const inputIndex = input.dataset.inputIndex
    const value = input.value

    // Save to server
    this.saveToServer(inputIndex, value)
  }

  async saveToServer(inputIndex, value) {
    try {
      const response = await fetch(`/works_orders/${this.worksOrderIdValue}/save_operation_input`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify({
          operation_position: this.operationPositionValue,
          input_index: inputIndex,
          value: value
        })
      })

      if (!response.ok) {
        console.error('Failed to save input:', response.statusText)
        this.showError(inputIndex)
      } else {
        this.showSuccess(inputIndex)
      }
    } catch (error) {
      console.error('Error saving input:', error)
      this.showError(inputIndex)
    }
  }

  showSuccess(inputIndex) {
    const input = this.inputTargets.find(i => i.dataset.inputIndex === inputIndex)
    if (input) {
      input.classList.remove('border-red-300', 'bg-red-50')
      input.classList.add('border-green-300', 'bg-green-50')

      setTimeout(() => {
        input.classList.remove('border-green-300', 'bg-green-50')
        input.classList.add('border-gray-300')
      }, 1000)
    }
  }

  showError(inputIndex) {
    const input = this.inputTargets.find(i => i.dataset.inputIndex === inputIndex)
    if (input) {
      input.classList.remove('border-green-300', 'bg-green-50')
      input.classList.add('border-red-300', 'bg-red-50')

      setTimeout(() => {
        input.classList.remove('border-red-300', 'bg-red-50')
        input.classList.add('border-gray-300')
      }, 3000)
    }
  }

  focusFirstEmptyInput() {
    const emptyInput = this.inputTargets.find(input => input.value === '')
    if (emptyInput) {
      emptyInput.focus()
    }
  }

  getCSRFToken() {
    const token = document.querySelector('meta[name="csrf-token"]')
    return token ? token.getAttribute('content') : ''
  }

  // Handle keyboard navigation between inputs
  handleKeyDown(event) {
    if (event.key === 'Tab' || event.key === 'Enter') {
      const currentInput = event.target
      const currentIndex = parseInt(currentInput.dataset.inputIndex)
      const nextInput = this.inputTargets.find(input =>
        parseInt(input.dataset.inputIndex) === currentIndex + 1
      )

      if (nextInput && event.key === 'Enter') {
        event.preventDefault()
        nextInput.focus()
      }
    }
  }
}
