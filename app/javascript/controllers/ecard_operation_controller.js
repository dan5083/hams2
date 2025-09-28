// app/javascript/controllers/ecard_operation_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["signOffButton", "batchSignoffs"]
  static values = {
    position: Number,
    worksOrderId: String,
    signedOff: Boolean,
    displayName: String,
    batchIndependent: Boolean
  }

  connect() {
    this.setupBatchTracking()
    if (this.signedOffValue) {
      this.markAsSignedOff()
    }
  }

  setupBatchTracking() {
    if (this.batchIndependentValue) {
      // Batch-independent operations (Contract Review, Final Inspection, Pack)
      // Don't need batch tracking
      return
    }

    // Set up batch tracking for regular operations
    this.setupBatchListener()
  }

  setupBatchListener() {
    document.addEventListener('batch-manager:batchAdded', () => this.updateBatchSignoffs())
    document.addEventListener('batch-manager:batchUpdated', () => this.updateBatchSignoffs())
    document.addEventListener('batch-manager:batchRemoved', () => this.updateBatchSignoffs())
  }

  updateBatchSignoffs() {
    // This is now handled by the batch manager controller
    // which updates all operation sign-offs when batches change
  }

  beforeSignOff(event) {
    if (this.batchIndependentValue) {
      return this.handleBatchIndependentSignOff(event)
    }
    return this.handleBatchDependentSignOff(event)
  }

  handleBatchIndependentSignOff(event) {
    // Contract review, final inspection, and pack can always be signed off
    return true
  }

  handleBatchDependentSignOff(event) {
    const batchManager = this.getBatchManagerController()
    if (!batchManager) {
      alert('Batch management system not available. Please refresh the page.')
      event.preventDefault()
      return false
    }

    const activeBatches = batchManager.getActiveBatches()
    if (activeBatches.length === 0) {
      alert('No batches found. Please create batches first.')
      event.preventDefault()
      return false
    }

    // For batch-dependent operations, the batch ID should be included in the form
    const form = event.target.closest('form')
    const batchId = form ? form.querySelector('input[name="batch_id"]')?.value : null

    if (!batchId) {
      alert('No batch specified for this operation.')
      event.preventDefault()
      return false
    }

    return true
  }

  getBatchManagerController() {
    const batchManagerElement = document.querySelector('[data-controller*="batch-manager"]')
    if (batchManagerElement) {
      return this.application.getControllerForElementAndIdentifier(
        batchManagerElement,
        'batch-manager'
      )
    }
    return null
  }

  markAsSignedOff() {
    // Update the row styling
    this.element.classList.add("bg-green-50")

    // For batch-independent operations, replace the single button
    if (this.batchIndependentValue && this.hasSignOffButtonTarget) {
      const buttonContainer = this.signOffButtonTarget.parentElement
      if (buttonContainer) {
        buttonContainer.innerHTML = `
          <div class="w-10 h-10 rounded-full bg-green-500 border-2 border-green-600 flex items-center justify-center">
            <span class="text-white text-lg font-bold">✓</span>
          </div>
        `
      }
    }
  }

  // Method called after successful sign-off
  operationSignedOff(batchId = null) {
    this.signedOffValue = true

    if (this.batchIndependentValue) {
      this.markAsSignedOff()
    }

    // Notify the main ecard controller
    const ecardEvent = new CustomEvent('ecard:operationSignedOff', {
      detail: {
        operationPosition: this.positionValue,
        operationName: this.displayNameValue,
        batchId: batchId,
        batchIndependent: this.batchIndependentValue
      },
      bubbles: true
    })
    this.element.dispatchEvent(ecardEvent)

    // Update batch progress if this is a batch-dependent operation
    if (!this.batchIndependentValue && batchId) {
      const batchManager = this.getBatchManagerController()
      if (batchManager) {
        batchManager.updateBatchProgress(batchId, this.positionValue)
      }
    }
  }
}
