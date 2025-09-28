// app/javascript/controllers/batch_manager_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "batchList",
    "addBatchForm",
    "newBatchQuantity",
    "batchSuggestion",
    "warningMessage",
    "batchSignoffHeader",
    "operationSignoffs"
  ]

  static values = {
    worksOrderId: String,
    totalQuantity: Number,
    batches: Array
  }

  connect() {
    this.initializeBatches()
    this.updateDisplay()
    this.setupBatchSuggestionListener()
  }

  setupBatchSuggestionListener() {
    if (this.hasNewBatchQuantityTarget) {
      this.newBatchQuantityTarget.addEventListener('input', () => {
        this.updateBatchSuggestion()
      })
    }
  }

  updateBatchSuggestion() {
    if (!this.hasBatchSuggestionTarget || !this.hasNewBatchQuantityTarget) return

    const batchSize = parseInt(this.newBatchQuantityTarget.value)
    if (!batchSize || batchSize <= 0) {
      this.batchSuggestionTarget.textContent = ''
      return
    }

    const totalQuantity = this.totalQuantityValue
    const numberOfBatches = Math.ceil(totalQuantity / batchSize)
    const lastBatchQuantity = totalQuantity - (batchSize * (numberOfBatches - 1))

    if (numberOfBatches === 1) {
      this.batchSuggestionTarget.textContent = `Suggested: 1 batch of ${totalQuantity} parts`
    } else {
      const regularBatches = numberOfBatches - 1
      this.batchSuggestionTarget.textContent =
        `Suggested: ${numberOfBatches} batches (${regularBatches}×${batchSize} + 1×${lastBatchQuantity})`
    }
  }

  updateDisplay() {
    this.renderBatches()
    this.updateQuantityCheck()
    this.updateBatchSignoffHeaders()
  }

  initializeBatches() {
    if (!this.batchesValue || this.batchesValue.length === 0) {
      this.batchesValue = []
    }
    this.renderBatches()
  }

  addBatch() {
    const quantity = parseInt(this.newBatchQuantityTarget.value)

    if (!quantity || quantity <= 0) {
      this.showWarning("Please enter a valid quantity greater than 0")
      return
    }

    this.createSingleBatch(quantity)
  }

  createSuggestedBatches() {
    const batchSize = parseInt(this.newBatchQuantityTarget.value)

    if (!batchSize || batchSize <= 0) {
      this.showWarning("Please enter a batch size first")
      return
    }

    const totalQuantity = this.totalQuantityValue
    const numberOfBatches = Math.ceil(totalQuantity / batchSize)
    const lastBatchQuantity = totalQuantity - (batchSize * (numberOfBatches - 1))

    const confirmMessage = numberOfBatches === 1
      ? `Create 1 batch of ${totalQuantity} parts?`
      : `Create ${numberOfBatches} batches (${numberOfBatches - 1}×${batchSize} + 1×${lastBatchQuantity})?`

    if (!confirm(confirmMessage)) {
      return
    }

    this.batchesValue = []

    for (let i = 1; i < numberOfBatches; i++) {
      this.createSingleBatch(batchSize, i)
    }

    this.createSingleBatch(lastBatchQuantity, numberOfBatches)

    this.newBatchQuantityTarget.value = ''
    this.updateDisplay()
  }

  createSingleBatch(quantity, batchNumber = null) {
    const newBatch = {
      id: `batch_${Date.now()}_${Math.random()}`,
      number: batchNumber || (this.batchesValue.length + 1),
      quantity: quantity,
      status: 'active',
      createdAt: new Date().toISOString(),
      currentOperation: 1
    }

    this.batchesValue = [...this.batchesValue, newBatch]
    this.notifyBatchAdded(newBatch)

    if (batchNumber === null) {
      this.newBatchQuantityTarget.value = ''
      this.updateDisplay()
    }
  }

  removeBatch(event) {
    const batchId = event.target.dataset.batchId
    const batchNumber = event.target.dataset.batchNumber

    if (!confirm(`Remove Batch ${batchNumber}? This cannot be undone.`)) {
      return
    }

    this.batchesValue = this.batchesValue.filter(batch => batch.id !== batchId)
    this.updateDisplay()
    this.notifyBatchRemoved(batchId)
  }

  renderBatches() {
    if (!this.hasBatchListTarget) return

    if (this.batchesValue.length === 0) {
      this.batchListTarget.innerHTML = `
        <div class="text-center text-gray-500 py-4 text-sm">
          No batches created yet. Add a batch to start processing.
        </div>
      `
      return
    }

    const batchesHtml = this.batchesValue.map(batch => this.renderBatch(batch)).join('')
    this.batchListTarget.innerHTML = batchesHtml
  }

  renderBatch(batch) {
    const statusClass = this.getBatchStatusClass(batch.status)
    const statusText = this.getBatchStatusText(batch.status)

    return `
      <div class="border border-gray-300 rounded p-3 ${statusClass}">
        <div class="flex justify-between items-center">
          <div class="flex items-center space-x-3">
            <span class="font-bold text-lg">B${batch.number}</span>
            <span class="text-sm font-medium">${batch.quantity} parts</span>
            <span class="text-xs px-2 py-1 rounded ${this.getStatusBadgeClass(batch.status)}">
              ${statusText}
            </span>
          </div>
          <div class="flex items-center space-x-2">
            <span class="text-xs text-gray-500">
              Created: ${new Date(batch.createdAt).toLocaleDateString()}
            </span>
            <button type="button"
                    class="text-red-500 hover:text-red-700 text-sm"
                    data-batch-id="${batch.id}"
                    data-batch-number="${batch.number}"
                    data-action="click->batch-manager#removeBatch">
              Remove
            </button>
          </div>
        </div>

        <div class="mt-2 text-xs text-gray-600">
          Current operation: Op ${batch.currentOperation || 1}
        </div>
      </div>
    `
  }

  // NEW: Update batch sign-off headers in operations table
  updateBatchSignoffHeaders() {
    if (this.hasBatchSignoffHeaderTarget) {
      if (this.batchesValue.length === 0) {
        this.batchSignoffHeaderTarget.innerHTML = `
          <div class="text-center text-gray-500 text-xs">No Batches</div>
        `
      } else {
        const headersHtml = this.batchesValue.map(batch =>
          `<div class="text-center px-2 py-1 min-w-[3rem] text-xs font-medium">B${batch.number}</div>`
        ).join('')

        this.batchSignoffHeaderTarget.innerHTML = `
          <div class="flex gap-1">
            ${headersHtml}
          </div>
        `
      }
    }

    // Update all operation sign-off areas
    this.updateOperationSignoffs()
  }

  // NEW: Update sign-off buttons for all operations
  updateOperationSignoffs() {
    const operationSignoffElements = this.operationSignoffsTargets ||
      document.querySelectorAll('[data-batch-manager-target="operationSignoffs"]')

    operationSignoffElements.forEach(element => {
      const operationPosition = element.dataset.operationPosition
      const isBatchIndependent = element.closest('[data-ecard-operation-batch-independent-value="true"]')

      if (isBatchIndependent) {
        // Skip batch-independent operations
        return
      }

      if (this.batchesValue.length === 0) {
        element.innerHTML = `
          <div class="text-center text-gray-400 text-xs py-3">
            Create batches<br>to sign off
          </div>
        `
      } else {
        const signoffButtonsHtml = this.batchesValue.map(batch =>
          this.renderBatchSignoffButton(batch, operationPosition)
        ).join('')

        element.innerHTML = `
          <div class="flex gap-1">
            ${signoffButtonsHtml}
          </div>
        `
      }
    })
  }

  // NEW: Render individual batch sign-off button
  renderBatchSignoffButton(batch, operationPosition) {
    const isSignedOff = this.isBatchOperationSignedOff(batch.id, operationPosition)

    if (isSignedOff) {
      return `
        <div class="w-10 h-10 rounded-full bg-green-500 border-2 border-green-600 flex items-center justify-center">
          <span class="text-white text-lg font-bold">✓</span>
        </div>
      `
    } else {
      return `
        <form action="/works_orders/${this.worksOrderIdValue}/sign_off_operation" method="post" class="inline">
          <input type="hidden" name="_method" value="patch">
          <input type="hidden" name="authenticity_token" value="${this.getCSRFToken()}">
          <input type="hidden" name="operation_position" value="${operationPosition}">
          <input type="hidden" name="batch_id" value="${batch.id}">
          <button type="submit"
                  class="w-10 h-10 rounded-full bg-gray-200 hover:bg-green-400 border-2 border-gray-300 hover:border-green-500 transition-all duration-200"
                  title="Sign off Operation ${operationPosition} for Batch ${batch.number}"
                  onclick="return confirm('Sign off Operation ${operationPosition} for Batch ${batch.number}?')">
          </button>
        </form>
      `
    }
  }

  // NEW: Check if a specific batch/operation combination is signed off
  isBatchOperationSignedOff(batchId, operationPosition) {
    // This would check against the works order's customised_process_data
    // For now, return false - this will be implemented with server-side data
    return false
  }

  // NEW: Get CSRF token for forms
  getCSRFToken() {
    const token = document.querySelector('meta[name="csrf-token"]')
    return token ? token.getAttribute('content') : ''
  }

  getBatchStatusClass(status) {
    switch (status) {
      case 'active': return 'bg-blue-50 border-blue-200'
      case 'processing': return 'bg-yellow-50 border-yellow-200'
      case 'complete': return 'bg-green-50 border-green-200'
      default: return 'bg-gray-50 border-gray-200'
    }
  }

  getBatchStatusText(status) {
    switch (status) {
      case 'active': return 'Ready'
      case 'processing': return 'In Progress'
      case 'complete': return 'Complete'
      default: return 'Unknown'
    }
  }

  getStatusBadgeClass(status) {
    switch (status) {
      case 'active': return 'bg-blue-100 text-blue-800'
      case 'processing': return 'bg-yellow-100 text-yellow-800'
      case 'complete': return 'bg-green-100 text-green-800'
      default: return 'bg-gray-100 text-gray-800'
    }
  }

  updateQuantityCheck() {
    const totalAssigned = this.batchesValue.reduce((sum, batch) => sum + batch.quantity, 0)
    const remaining = this.totalQuantityValue - totalAssigned

    // Color code the remaining quantity and show warnings
    this.checkQuantityWarning(totalAssigned, remaining)
  }

  checkQuantityWarning(totalAssigned, remaining) {
    let warningMessage = ''

    if (remaining < 0) {
      warningMessage = `Hmm, where did the extra ${Math.abs(remaining)} parts come from? 🤔`
    } else if (remaining > 0 && this.batchesValue.length > 0) {
      warningMessage = `${remaining} parts not yet assigned to batches`
    }

    if (this.hasWarningMessageTarget) {
      if (warningMessage) {
        this.warningMessageTarget.textContent = warningMessage
        this.warningMessageTarget.classList.remove('hidden')
      } else {
        this.warningMessageTarget.classList.add('hidden')
      }
    }
  }

  showWarning(message) {
    if (this.hasWarningMessageTarget) {
      this.warningMessageTarget.textContent = message
      this.warningMessageTarget.classList.remove('hidden')

      setTimeout(() => {
        this.warningMessageTarget.classList.add('hidden')
      }, 5000)
    }
  }

  getActiveBatches() {
    return this.batchesValue.filter(batch =>
      batch.status === 'active' || batch.status === 'processing'
    )
  }

  updateBatchProgress(batchId, operationPosition) {
    const batch = this.batchesValue.find(b => b.id === batchId)
    if (batch) {
      batch.currentOperation = Math.max(batch.currentOperation || 1, operationPosition + 1)

      if (batch.currentOperation > this.getTotalOperations()) {
        batch.status = 'complete'
      } else {
        batch.status = 'processing'
      }

      this.renderBatches()
      this.updateOperationSignoffs()
      this.notifyBatchUpdated(batch)
    }
  }

  getTotalOperations() {
    return parseInt(this.element.dataset.totalOperations) || 10
  }

  // Event dispatching
  notifyBatchAdded(batch) {
    const event = new CustomEvent('batch-manager:batchAdded', {
      detail: batch,
      bubbles: true
    })
    document.dispatchEvent(event)
  }

  notifyBatchRemoved(batchId) {
    const event = new CustomEvent('batch-manager:batchRemoved', {
      detail: { batchId },
      bubbles: true
    })
    document.dispatchEvent(event)
  }

  notifyBatchUpdated(batch) {
    const event = new CustomEvent('batch-manager:batchUpdated', {
      detail: batch,
      bubbles: true
    })
    document.dispatchEvent(event)
  }

  async saveBatches() {
    try {
      console.log('Saving batches:', this.batchesValue)
    } catch (error) {
      console.error('Failed to save batches:', error)
      this.showWarning('Failed to save batch configuration')
    }
  }
}
