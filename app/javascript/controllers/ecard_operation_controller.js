// app/javascript/controllers/ecard_operation_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["signOffButton"]
  static values = {
    position: Number,
    worksOrderId: String
  }

  connect() {
    this.loadOperationState()
  }

  loadOperationState() {
    // Could load any operation-specific state here
    // For example, expanded/collapsed state, notes, etc.
  }

  beforeSignOff(event) {
    // Additional confirmation or validation before sign-off
    const confirmation = confirm(
      `Are you sure you want to sign off Operation ${this.positionValue}?\n\nThis action cannot be undone.`
    )

    if (!confirmation) {
      event.preventDefault()
      return false
    }

    // Show loading state
    this.showLoadingState()
  }

  showLoadingState() {
    if (this.hasSignOffButtonTarget) {
      this.signOffButtonTarget.disabled = true
      this.signOffButtonTarget.textContent = "Signing off..."
      this.signOffButtonTarget.classList.add("opacity-50")
    }
  }

  // Could add methods for:
  // - Expanding/collapsing operation details
  // - Adding operation notes
  // - Validation before sign-off
  // - Real-time status updates
}
