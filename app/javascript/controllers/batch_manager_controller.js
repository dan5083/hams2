// app/javascript/controllers/batch_manager_controller.js - Fixed with persistence
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "batchContainer",
    "batchRows",
    "batchTableHeader",
    "emptyState",
    "newBatchQuantity",
    "batchSuggestion",
    "warningMessage",
    "batchSummary",
    "totalBatches",
    "assignedQuantity",
    "remainingQuantity",
    "createAllButton"
  ]

  static values = {
    worksOrderId: String,
    totalQuantity: Number,
    batches: Array
  }

  connect() {
    console.log('🔧 Batch Manager Connected')
    console.log('📊 Initial batches:', this.batchesValue)

    this.initializeBatches()
    this.updateDisplay()
    this.setupBatchSuggestionListener()
    this.updateOperationHeaders()
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

    const remaining = this.getRemainingQuantity()
    const numberOfBatches = Math.ceil(remaining / batchSize)
    const lastBatchQuantity = remaining - (batchSize * (numberOfBatches - 1))

    if (numberOfBatches === 1) {
      this.batchSuggestionTarget.textContent = `Will create: 1 batch of ${remaining} parts`
    } else {
      const regularBatches = numberOfBatches - 1
      this.batchSuggestionTarget.textContent =
        `Will create: ${numberOfBatches} batches (${regularBatches}×${batchSize} + 1×${lastBatchQuantity})`
    }
  }

  initializeBatches() {
    // Ensure batches have required properties
    this.batchesValue = this.batchesValue.map((batch, index) => ({
      id: batch.id || `batch_${Date.now()}_${index}`,
      number: batch.number || (index + 1),
      quantity: parseInt(batch.quantity) || 0,
      status: batch.status || 'active',
      createdAt: batch.createdAt || new Date().toISOString(),
      currentOperation: batch.currentOperation || 1,
      ...batch
    }))
  }

  updateDisplay() {
    this.renderBatches()
    this.updateSummary()
    this.updateQuantityCheck()
    this.updateOperationHeaders()
  }

  renderBatches() {
    if (this.batchesValue.length === 0) {
      this.showEmptyState()
    } else {
      this.showBatchTable()
    }
  }

  showEmptyState() {
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.remove('hidden')
    }
    if (this.hasBatchTableHeaderTarget) {
      this.batchTableHeaderTarget.classList.add('hidden')
    }
    if (this.hasBatchRowsTarget) {
      this.batchRowsTarget.innerHTML = ''
    }
  }

  showBatchTable() {
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.add('hidden')
    }
    if (this.hasBatchTableHeaderTarget) {
      this.batchTableHeaderTarget.classList.remove('hidden')
    }

    if (this.hasBatchRowsTarget) {
      const batchesHtml = this.batchesValue.map(batch => this.renderBatchRow(batch)).join('')
      this.batchRowsTarget.innerHTML = batchesHtml
    }
  }

  renderBatchRow(batch) {
    const statusClass = this.getBatchStatusClass(batch.status)
    const progressText = this.getBatchProgressText(batch)

    return `
      <div class="border-l border-r border-b border-gray-300 bg-white hover:bg-gray-50">
        <div class="grid grid-cols-12 gap-2 p-3 text-sm items-center">
          <!-- Batch ID -->
          <div class="col-span-2">
            <span class="font-bold text-lg text-blue-600">B${batch.number}</span>
          </div>

          <!-- Editable Quantity -->
          <div class="col-span-2">
            <input type="number"
                   value="${batch.quantity}"
                   min="1"
                   max="${this.totalQuantityValue}"
                   class="w-full border border-gray-300 rounded px-2 py-1 text-sm"
                   data-batch-id="${batch.id}"
                   data-action="change->batch-manager#updateBatchQuantity">
          </div>

          <!-- Status -->
          <div class="col-span-2">
            <span class="px-2 py-1 rounded text-xs font-medium ${this.getStatusBadgeClass(batch.status)}">
              ${this.getBatchStatusText(batch.status)}
            </span>
          </div>

          <!-- Progress -->
          <div class="col-span-3">
            <div class="text-xs text-gray-600">${progressText}</div>
          </div>

          <!-- Created Date -->
          <div class="col-span-2">
            <div class="text-xs text-gray-500">
              ${new Date(batch.createdAt).toLocaleDateString()}
            </div>
          </div>

          <!-- Actions -->
          <div class="col-span-1">
            <button type="button"
                    class="text-red-500 hover:text-red-700 text-sm font-medium"
                    data-batch-id="${batch.id}"
                    data-batch-number="${batch.number}"
                    data-action="click->batch-manager#removeBatch">
              Remove
            </button>
          </div>
        </div>
      </div>
    `
  }

  getBatchProgressText(batch) {
    const totalOps = parseInt(this.element.dataset.totalOperations) || 10
    const currentOp = batch.currentOperation || 1
    return `Op ${currentOp}/${totalOps}`
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

  updateSummary() {
    const totalBatches = this.batchesValue.length
    const assignedQuantity = this.getAssignedQuantity()
    const remainingQuantity = this.getRemainingQuantity()

    if (this.hasTotalBatchesTarget) {
      this.totalBatchesTarget.textContent = totalBatches
    }
    if (this.hasAssignedQuantityTarget) {
      this.assignedQuantityTarget.textContent = assignedQuantity
    }
    if (this.hasRemainingQuantityTarget) {
      this.remainingQuantityTarget.textContent = remainingQuantity
    }
  }

  getAssignedQuantity() {
    return this.batchesValue.reduce((sum, batch) => sum + parseInt(batch.quantity), 0)
  }

  getRemainingQuantity() {
    return Math.max(0, this.totalQuantityValue - this.getAssignedQuantity())
  }

  updateQuantityCheck() {
    const remaining = this.getRemainingQuantity()
    let warningMessage = ''

    if (remaining < 0) {
      warningMessage = `Over-allocated by ${Math.abs(remaining)} parts. Please adjust batch quantities.`
    } else if (remaining > 0 && this.batchesValue.length > 0) {
      warningMessage = `${remaining} parts not yet assigned to batches.`
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

  // FIXED: Update operation headers with horizontal batch columns
  updateOperationHeaders() {
    const headerElements = document.querySelectorAll('[data-batch-manager-target="batchSignoffHeader"]')
    const operationElements = document.querySelectorAll('[data-batch-manager-target="operationSignoffs"]')

    headerElements.forEach(element => {
      if (this.batchesValue.length === 0) {
        element.innerHTML = `
          <div class="text-center text-gray-500 text-xs py-2">No Batches</div>
        `
        element.style.minWidth = '120px'
      } else {
        const headersHtml = this.batchesValue.map(batch =>
          `<div class="text-center px-1 py-1 min-w-[50px] text-xs font-medium border-r border-gray-200 last:border-r-0">
            B${batch.number}
          </div>`
        ).join('')

        element.innerHTML = `
          <div class="flex bg-gray-50 border border-gray-300 rounded">
            ${headersHtml}
          </div>
        `
        element.style.minWidth = `${this.batchesValue.length * 55}px`
      }
    })

    // Update operation sign-off buttons
    operationElements.forEach(element => {
      const operationPosition = element.dataset.operationPosition
      const isBatchIndependent = element.closest('[data-ecard-operation-batch-independent-value="true"]')

      if (isBatchIndependent) {
        return // Skip batch-independent operations
      }

      if (this.batchesValue.length === 0) {
        element.innerHTML = `
          <div class="text-center text-gray-400 text-xs py-3">
            Create batches<br>to sign off
          </div>
        `
        element.style.minWidth = '120px'
      } else {
        const buttonsHtml = this.batchesValue.map(batch =>
          this.renderBatchSignoffButton(batch, operationPosition)
        ).join('')

        element.innerHTML = `
          <div class="flex border border-gray-300 rounded overflow-hidden">
            ${buttonsHtml}
          </div>
        `
        element.style.minWidth = `${this.batchesValue.length * 55}px`
      }
    })
  }

  renderBatchSignoffButton(batch, operationPosition) {
    const isSignedOff = this.isBatchOperationSignedOff(batch.id, operationPosition)

    if (isSignedOff) {
      return `
        <div class="w-12 h-12 bg-green-500 border-r border-gray-300 last:border-r-0 flex items-center justify-center">
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
                  class="w-12 h-12 bg-gray-100 hover:bg-green-400 border-r border-gray-300 last:border-r-0 transition-all duration-200 flex items-center justify-center"
                  title="Sign off Op ${operationPosition} for Batch ${batch.number}"
                  onclick="return confirm('Sign off Operation ${operationPosition} for Batch ${batch.number}?')">
            <span class="text-gray-500 hover:text-white">○</span>
          </button>
        </form>
      `
    }
  }

  isBatchOperationSignedOff(batchId, operationPosition) {
    // This will be checked against server data - for now return false
    return false
  }

  getCSRFToken() {
    const token = document.querySelector('meta[name="csrf-token"]')
    return token ? token.getAttribute('content') : ''
  }

  // Event handlers
  addBatch() {
    const quantity = parseInt(this.newBatchQuantityTarget.value)

    if (!quantity || quantity <= 0) {
      this.showWarning("Please enter a valid quantity greater than 0")
      return
    }

    const remaining = this.getRemainingQuantity()
    if (quantity > remaining) {
      this.showWarning(`Cannot create batch of ${quantity} parts. Only ${remaining} parts remaining.`)
      return
    }

    this.createSingleBatch(quantity)
    this.newBatchQuantityTarget.value = ''
  }

  createSuggestedBatches() {
    const batchSize = parseInt(this.newBatchQuantityTarget.value)
    const remaining = this.getRemainingQuantity()

    if (!batchSize || batchSize <= 0) {
      this.showWarning("Please enter a batch size first")
      return
    }

    if (remaining <= 0) {
      this.showWarning("No remaining quantity to assign to batches")
      return
    }

    const numberOfBatches = Math.ceil(remaining / batchSize)
    const lastBatchQuantity = remaining - (batchSize * (numberOfBatches - 1))

    const confirmMessage = numberOfBatches === 1
      ? `Create 1 batch of ${remaining} parts?`
      : `Create ${numberOfBatches} batches (${numberOfBatches - 1}×${batchSize} + 1×${lastBatchQuantity})?`

    if (!confirm(confirmMessage)) return

    // Create the batches
    for (let i = 1; i < numberOfBatches; i++) {
      this.createSingleBatch(batchSize, this.batchesValue.length + 1, false)
    }
    this.createSingleBatch(lastBatchQuantity, this.batchesValue.length + 1, false)

    this.newBatchQuantityTarget.value = ''
    this.updateDisplay()
    this.saveBatches()
  }

  createSingleBatch(quantity, batchNumber = null, shouldSave = true) {
    const newBatch = {
      id: `batch_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      number: batchNumber || (this.batchesValue.length + 1),
      quantity: parseInt(quantity),
      status: 'active',
      createdAt: new Date().toISOString(),
      currentOperation: 1
    }

    this.batchesValue = [...this.batchesValue, newBatch]

    if (shouldSave) {
      this.updateDisplay()
      this.saveBatches()
    }
  }

  updateBatchQuantity(event) {
    const batchId = event.target.dataset.batchId
    const newQuantity = parseInt(event.target.value)

    if (!newQuantity || newQuantity <= 0) {
      this.showWarning("Batch quantity must be greater than 0")
      event.target.value = 1
      return
    }

    const batch = this.batchesValue.find(b => b.id === batchId)
    if (batch) {
      batch.quantity = newQuantity
      this.batchesValue = [...this.batchesValue] // Trigger reactivity
      this.updateSummary()
      this.updateQuantityCheck()
      this.saveBatches()
    }
  }

  removeBatch(event) {
    const batchId = event.target.dataset.batchId
    const batchNumber = event.target.dataset.batchNumber

    if (!confirm(`Remove Batch ${batchNumber}? This cannot be undone.`)) return

    this.batchesValue = this.batchesValue.filter(batch => batch.id !== batchId)

    // Renumber remaining batches
    this.batchesValue.forEach((batch, index) => {
      batch.number = index + 1
    })

    this.updateDisplay()
    this.saveBatches()
  }

  // FIXED: Persistence - save to server
  async saveBatches() {
    try {
      const response = await fetch(`/works_orders/${this.worksOrderIdValue}/save_batches`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({
          batches: this.batchesValue
        })
      })

      if (!response.ok) {
        throw new Error('Failed to save batches')
      }

      console.log('✅ Batches saved successfully')
    } catch (error) {
      console.error('❌ Failed to save batches:', error)
      this.showWarning('Failed to save batch configuration')
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

  // Batch progress management
  updateBatchProgress(batchId, operationPosition) {
    const batch = this.batchesValue.find(b => b.id === batchId)
    if (batch) {
      batch.currentOperation = Math.max(batch.currentOperation || 1, operationPosition + 1)
      const totalOps = parseInt(this.element.dataset.totalOperations) || 10

      if (batch.currentOperation > totalOps) {
        batch.status = 'complete'
      } else {
        batch.status = 'processing'
      }

      this.updateDisplay()
      this.saveBatches()
    }
  }
}
