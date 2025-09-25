// app/javascript/controllers/batch_tracker_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "currentBatch",
    "batchStatus",
    "signOffSection"
  ]

  static values = {
    operationPosition: Number,
    worksOrderId: String
  }

  connect() {
    this.setupBatchListener()
    this.loadCurrentBatch()
  }

  setupBatchListener() {
    // Listen for batch manager events
    this.element.addEventListener('batch-manager:batchAdded', (event) => {
      this.handleBatchAdded(event.detail)
    })

    this.element.addEventListener('batch-manager:batchUpdated', (event) => {
      this.handleBatchUpdated(event.detail)
    })

    this.element.addEventListener('batch-manager:batchRemoved', (event) => {
      this.handleBatchRemoved(event.detail)
    })
  }

  loadCurrentBatch() {
    // Get current active batches from batch manager
    this.updateCurrentBatchDisplay()
  }

  handleBatchAdded(batch) {
    this.updateCurrentBatchDisplay()
  }

  handleBatchUpdated(batch) {
    this.updateCurrentBatchDisplay()
  }

  handleBatchRemoved(batchId) {
    this.updateCurrentBatchDisplay()
  }

  updateCurrentBatchDisplay() {
    const batchManager = this.getBatchManagerController()
    if (!batchManager) return

    const activeBatches = batchManager.getActiveBatches()
    const currentBatch = this.getCurrentBatchForOperation(activeBatches)

    if (this.hasCurrentBatchTarget) {
      if (currentBatch) {
        this.currentBatchTarget.innerHTML = `
          <div class="bg-blue-50 border border-blue-200 rounded p-3 mb-4">
            <div class="flex justify-between items-center">
              <div class="flex items-center space-x-3">
                <span class="font-bold text-blue-800">Processing Batch ${currentBatch.number}</span>
                <span class="text-sm text-blue-600">${currentBatch.quantity} parts</span>
              </div>
              <span class="text-xs px-2 py-1 bg-blue-100 text-blue-700 rounded">
                Op ${this.operationPositionValue}
              </span>
            </div>
            <div class="mt-2 text-xs text-blue-600">
              Sign off when this batch is complete for this operation
            </div>
          </div>
        `

        // Show sign off section
        if (this.hasSignOffSectionTarget) {
          this.signOffSectionTarget.classList.remove('hidden')
        }
      } else {
        this.currentBatchTarget.innerHTML = `
          <div class="bg-gray-50 border border-gray-200 rounded p-3 mb-4">
            <div class="text-center text-gray-600 text-sm">
              <div class="font-medium">No active batch for this operation</div>
              <div class="text-xs mt-1">Create a batch in Batch Management to start processing</div>
            </div>
          </div>
        `

        // Hide sign off section
        if (this.hasSignOffSectionTarget) {
          this.signOffSectionTarget.classList.add('hidden')
        }
      }
    }
  }

  getCurrentBatchForOperation(activeBatches) {
    // Find batch that's at or behind this operation
    return activeBatches.find(batch =>
      (batch.currentOperation || 1) <= this.operationPositionValue
    )
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

  // Called when operation is signed off
  onOperationSignedOff() {
    const batchManager = this.getBatchManagerController()
    if (!batchManager) return

    const activeBatches = batchManager.getActiveBatches()
    const currentBatch = this.getCurrentBatchForOperation(activeBatches)

    if (currentBatch) {
      // Update batch progress
      batchManager.updateBatchProgress(currentBatch.id, this.operationPositionValue)

      // Dispatch event for main ecard controller
      this.dispatch('operationCompleted', {
        detail: {
          operationPosition: this.operationPositionValue,
          batchId: currentBatch.id,
          batchNumber: currentBatch.number,
          quantity: currentBatch.quantity
        }
      })
    }
  }

  // Validate before sign-off
  validateBeforeSignOff() {
    const batchManager = this.getBatchManagerController()
    if (!batchManager) {
      alert('Batch management system not available. Please refresh the page.')
      return false
    }

    const activeBatches = batchManager.getActiveBatches()
    const currentBatch = this.getCurrentBatchForOperation(activeBatches)

    if (!currentBatch) {
      alert('No active batch found for this operation. Please create a batch first.')
      return false
    }

    const confirmation = confirm(
      `Sign off Operation ${this.operationPositionValue} for Batch ${currentBatch.number} (${currentBatch.quantity} parts)?`
    )

    if (confirmation) {
      // Mark this batch as processed for this operation
      this.onOperationSignedOff()
    }

    return confirmation
  }
}
