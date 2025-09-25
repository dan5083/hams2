// app/javascript/controllers/batch_manager_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "batchList",
    "addBatchForm",
    "newBatchQuantity",
    "totalAssigned",
    "totalRemaining",
    "warningMessage"
  ]

  static values = {
    worksOrderId: String,
    totalQuantity: Number,
    batches: Array
  }

  connect() {
    this.initializeBatches()
    this.updateTotals()
  }

  initializeBatches() {
    // If no batches exist, start with empty array
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

    const newBatch = {
      id: `batch_${Date.now()}`,
      number: this.batchesValue.length + 1,
      quantity: quantity,
      status: 'active',
      createdAt: new Date().toISOString(),
      currentOperation: 1
    }

    this.batchesValue = [...this.batchesValue, newBatch]
    this.newBatchQuantityTarget.value = ''

    this.renderBatches()
    this.updateTotals()
    this.notifyBatchAdded(newBatch)
  }

  removeBatch(event) {
    const batchId = event.target.dataset.batchId
    const batchNumber = event.target.dataset.batchNumber

    if (!confirm(`Remove Batch ${batchNumber}? This cannot be undone.`)) {
      return
    }

    this.batchesValue = this.batchesValue.filter(batch => batch.id !== batchId)
    this.renderBatches()
    this.updateTotals()
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

  updateTotals() {
    const totalAssigned = this.batchesValue.reduce((sum, batch) => sum + batch.quantity, 0)
    const remaining = this.totalQuantityValue - totalAssigned

    if (this.hasTotalAssignedTarget) {
      this.totalAssignedTarget.textContent = totalAssigned
    }

    if (this.hasTotalRemainingTarget) {
      this.totalRemainingTarget.textContent = remaining

      // Color code the remaining quantity
      if (remaining < 0) {
        this.totalRemainingTarget.classList.add('text-orange-600', 'font-medium')
        this.totalRemainingTarget.classList.remove('text-green-600', 'text-gray-600')
      } else if (remaining === 0) {
        this.totalRemainingTarget.classList.add('text-green-600', 'font-medium')
        this.totalRemainingTarget.classList.remove('text-orange-600', 'text-gray-600')
      } else {
        this.totalRemainingTarget.classList.add('text-gray-600')
        this.totalRemainingTarget.classList.remove('text-orange-600', 'text-green-600')
      }
    }

    // Show warning if quantities don't match
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

      // Auto-hide after 5 seconds
      setTimeout(() => {
        this.warningMessageTarget.classList.add('hidden')
      }, 5000)
    }
  }

  // Get current active batches (for operations to process)
  getActiveBatches() {
    return this.batchesValue.filter(batch =>
      batch.status === 'active' || batch.status === 'processing'
    )
  }

  // Update batch status when operations are signed off
  updateBatchProgress(batchId, operationPosition) {
    const batch = this.batchesValue.find(b => b.id === batchId)
    if (batch) {
      batch.currentOperation = Math.max(batch.currentOperation || 1, operationPosition + 1)

      // Update status based on progress
      if (batch.currentOperation > this.getTotalOperations()) {
        batch.status = 'complete'
      } else {
        batch.status = 'processing'
      }

      this.renderBatches()
      this.notifyBatchUpdated(batch)
    }
  }

  getTotalOperations() {
    // This should come from the work order data
    return parseInt(this.element.dataset.totalOperations) || 10
  }

  // Event dispatching to notify other controllers
  notifyBatchAdded(batch) {
    this.dispatch('batchAdded', { detail: batch })
  }

  notifyBatchRemoved(batchId) {
    this.dispatch('batchRemoved', { detail: { batchId } })
  }

  notifyBatchUpdated(batch) {
    this.dispatch('batchUpdated', { detail: batch })
  }

  // Save batches to server (placeholder)
  async saveBatches() {
    try {
      // Could POST to server to save batch configuration
      console.log('Saving batches:', this.batchesValue)
    } catch (error) {
      console.error('Failed to save batches:', error)
      this.showWarning('Failed to save batch configuration')
    }
  }
}
