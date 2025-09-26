// app/javascript/controllers/ecard_operation_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["signOffButton", "statusBadge", "currentBatch", "batchQuantity"]
  static values = {
    position: Number,
    worksOrderId: String,
    signedOff: Boolean,
    displayName: String
  }

  connect() {
    this.setupBatchTracking()
    if (this.signedOffValue) {
      this.markAsSignedOff()
    }
  }

  setupBatchTracking() {
    // Only set up batch tracking for non-contract review operations
    if (!this.isContractReview()) {
      this.updateCurrentBatch()
      this.setupBatchListener()
    }
  }

  setupBatchListener() {
    document.addEventListener('batch-manager:batchAdded', () => this.updateCurrentBatch())
    document.addEventListener('batch-manager:batchUpdated', () => this.updateCurrentBatch())
    document.addEventListener('batch-manager:batchRemoved', () => this.updateCurrentBatch())
  }

  updateCurrentBatch() {
    const batchManager = this.getBatchManagerController()
    if (!batchManager) return

    const activeBatches = batchManager.getActiveBatches()
    const currentBatch = this.getCurrentBatchForOperation(activeBatches)

    this.displayBatchInfo(currentBatch)
    this.updateOperationStatus(currentBatch)
  }

  displayBatchInfo(currentBatch) {
    if (this.hasCurrentBatchTarget && this.hasBatchQuantityTarget) {
      if (currentBatch) {
        this.currentBatchTarget.innerHTML = `<span class="font-medium text-blue-600">B${currentBatch.number}</span>`
        this.batchQuantityTarget.innerHTML = `<span class="font-medium">${currentBatch.quantity}</span>`
      } else {
        this.currentBatchTarget.innerHTML = `<span class="text-gray-400">-</span>`
        this.batchQuantityTarget.innerHTML = `<span class="text-gray-400">-</span>`
      }
    }
  }

  updateOperationStatus(currentBatch) {
    if (this.hasStatusBadgeTarget && this.hasSignOffButtonTarget) {
      if (currentBatch) {
        this.statusBadgeTarget.textContent = 'Ready to Process'
        this.statusBadgeTarget.className = 'inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-green-100 text-green-800'
        this.signOffButtonTarget.disabled = false
        this.signOffButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
      } else {
        this.statusBadgeTarget.textContent = 'Waiting for Batch'
        this.statusBadgeTarget.className = 'inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-gray-100 text-gray-600'
        this.signOffButtonTarget.disabled = true
        this.signOffButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
      }
    }
  }

  beforeSignOff(event) {
    if (this.isContractReview()) {
      return this.handleContractReviewSignOff(event)
    }
    return this.handleRegularOperationSignOff(event)
  }

  handleContractReviewSignOff(event) {
    // Contract review can always be signed off
    return true
  }

  handleRegularOperationSignOff(event) {
    const batchManager = this.getBatchManagerController()
    if (!batchManager) {
      alert('Batch management system not available. Please refresh the page.')
      event.preventDefault()
      return false
    }

    const activeBatches = batchManager.getActiveBatches()
    const currentBatch = this.getCurrentBatchForOperation(activeBatches)

    if (!currentBatch) {
      alert('No active batch found for this operation. Please create a batch first.')
      event.preventDefault()
      return false
    }

    // Update batch progress when signed off
    this.updateBatchProgress(batchManager, currentBatch)
    return true
  }

  isContractReview() {
    return this.displayNameValue && this.displayNameValue.toLowerCase().includes('contract review')
  }

  getCurrentBatchForOperation(activeBatches) {
    return activeBatches.find(batch =>
      (batch.currentOperation || 1) <= this.positionValue
    )
  }

  updateBatchProgress(batchManager, batch) {
    if (batchManager && typeof batchManager.updateBatchProgress === 'function') {
      batchManager.updateBatchProgress(batch.id, this.positionValue)
    }
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

    // Update status badge
    if (this.hasStatusBadgeTarget) {
      this.statusBadgeTarget.textContent = "✓ Complete"
      this.statusBadgeTarget.className = "inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-green-100 text-green-800"
    }

    // Replace sign off button with checkmark
    if (this.hasSignOffButtonTarget) {
      const buttonCell = this.signOffButtonTarget.parentElement
      if (buttonCell) {
        buttonCell.innerHTML = '<span class="text-green-600 text-xs">✓</span>'
      }
    }
  }

  // Method called after successful sign-off
  operationSignedOff() {
    this.signedOffValue = true
    this.markAsSignedOff()

    // Notify the main ecard controller
    const ecardEvent = new CustomEvent('ecard:operationSignedOff', {
      detail: {
        operationPosition: this.positionValue,
        operationName: this.displayNameValue
      },
      bubbles: true
    })
    this.element.dispatchEvent(ecardEvent)
  }
}
