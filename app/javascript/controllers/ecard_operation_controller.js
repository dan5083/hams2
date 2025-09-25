// app/javascript/controllers/ecard_operation_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["signOffButton", "operationContent", "batchSection"]
  static values = {
    position: Number,
    worksOrderId: String,
    signedOff: Boolean,
    displayName: String
  }

  connect() {
    this.loadOperationState()
    this.setupOperationSpecificBehavior()
  }

  loadOperationState() {
    // Update UI based on signed-off status
    if (this.signedOffValue) {
      this.markAsSignedOff()
    }
  }

  setupOperationSpecificBehavior() {
    // Special behavior for contract review operations
    if (this.displayNameValue && this.displayNameValue.toLowerCase().includes('contract review')) {
      this.setupContractReviewBehavior()
    }
  }

  setupContractReviewBehavior() {
    // Contract review operations may not need batch tracking
    // Hide batch section if present
    if (this.hasBatchSectionTarget) {
      const batchTracker = this.batchSectionTarget.querySelector('[data-controller*="batch-tracker"]')
      if (batchTracker) {
        batchTracker.style.display = 'none'
      }
    }
  }

  beforeSignOff(event) {
    // Prevent default form submission temporarily
    event.preventDefault()

    // Special handling for contract review
    if (this.displayNameValue && this.displayNameValue.toLowerCase().includes('contract review')) {
      return this.handleContractReviewSignOff(event)
    }

    // For regular operations, validate batch tracking
    return this.handleRegularOperationSignOff(event)
  }

  handleContractReviewSignOff(event) {
    const confirmation = confirm(
      `Sign off Contract Review for Operation ${this.positionValue}?\n\nThis confirms that contract requirements have been reviewed and understood.`
    )

    if (confirmation) {
      this.showLoadingState()
      // Allow the form to submit
      event.target.closest('form').submit()
    }

    return confirmation
  }

  handleRegularOperationSignOff(event) {
    // Find associated batch tracker controller
    const batchTrackerElement = this.element.querySelector('[data-controller*="batch-tracker"]')
    let batchValidation = true

    if (batchTrackerElement) {
      // Get the batch tracker controller instance
      const batchController = this.application.getControllerForElementAndIdentifier(
        batchTrackerElement,
        'batch-tracker'
      )

      if (batchController && typeof batchController.validateBeforeSignOff === 'function') {
        batchValidation = batchController.validateBeforeSignOff()
      }
    }

    if (!batchValidation) {
      return false
    }

    // Final confirmation
    const confirmation = confirm(
      `Are you sure you want to sign off Operation ${this.positionValue}: ${this.displayNameValue}?\n\nThis action cannot be undone.`
    )

    if (confirmation) {
      this.showLoadingState()
      // Allow the form to submit
      event.target.closest('form').submit()
      return true
    }

    return false
  }

  showLoadingState() {
    if (this.hasSignOffButtonTarget) {
      this.signOffButtonTarget.disabled = true
      this.signOffButtonTarget.textContent = "Signing off..."
      this.signOffButtonTarget.classList.add("opacity-50", "cursor-not-allowed")
    }

    // Show loading indicator on the entire operation
    this.element.classList.add("opacity-75")
  }

  markAsSignedOff() {
    // Visual changes when operation is signed off
    this.element.classList.add("bg-green-50", "border-green-300")

    // Update any status indicators
    const statusElements = this.element.querySelectorAll('[data-operation-status]')
    statusElements.forEach(element => {
      element.textContent = "✓ Signed Off"
      element.classList.add("text-green-600", "font-semibold")
    })

    // Disable interactive elements
    const interactiveElements = this.element.querySelectorAll('input, button, select, textarea')
    interactiveElements.forEach(element => {
      if (!element.classList.contains('keep-enabled')) {
        element.disabled = true
      }
    })
  }

  // Method to expand/collapse operation details
  toggleDetails() {
    if (this.hasOperationContentTarget) {
      const isExpanded = !this.operationContentTarget.classList.contains('hidden')

      if (isExpanded) {
        this.operationContentTarget.classList.add('hidden')
        this.element.querySelector('[data-toggle-text]').textContent = 'Show Details'
      } else {
        this.operationContentTarget.classList.remove('hidden')
        this.element.querySelector('[data-toggle-text]').textContent = 'Hide Details'
      }
    }
  }

  // Method to save operation notes (if implemented)
  saveNotes() {
    const notesElement = this.element.querySelector('[data-operation-notes]')
    if (notesElement && notesElement.value.trim()) {
      // Could implement AJAX save of operation notes
      console.log(`Saving notes for operation ${this.positionValue}:`, notesElement.value)
    }
  }

  // Method called when batch tracker updates
  onBatchUpdate(event) {
    // Could update operation-level summaries based on batch data
    if (event.detail && event.detail.totalQuantity) {
      this.updateQuantitySummary(event.detail.totalQuantity)
    }
  }

  updateQuantitySummary(totalQuantity) {
    const summaryElement = this.element.querySelector('[data-quantity-summary]')
    if (summaryElement) {
      summaryElement.textContent = `Total processed: ${totalQuantity}`
    }
  }
}
