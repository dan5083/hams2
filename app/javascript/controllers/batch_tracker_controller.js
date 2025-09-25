// app/javascript/controllers/batch_tracker_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["batchContainer", "batchTemplate", "emptyState", "batchRow"]
  static values = {
    operationPosition: Number,
    worksOrderId: String
  }

  connect() {
    this.batchCount = 0
    this.loadExistingBatches()
  }

  addBatch() {
    this.batchCount++

    // Clone the template
    const template = this.batchTemplateTarget.content.cloneNode(true)
    const batchRow = template.querySelector('[data-batch-tracker-target="batchRow"]')

    // Set the batch number
    const batchNumber = batchRow.querySelector('[data-batch-tracker-target="batchNumber"]')
    batchNumber.textContent = `B${this.batchCount}`

    // Set current date and time
    const dateInput = batchRow.querySelector('[data-batch-tracker-target="dateInput"]')
    const timeInput = batchRow.querySelector('[data-batch-tracker-target="timeInput"]')

    const now = new Date()
    dateInput.value = now.toISOString().split('T')[0]
    timeInput.value = now.toTimeString().slice(0, 5)

    // Hide empty state and add the new row
    this.hideEmptyState()
    this.batchContainerTarget.appendChild(batchRow)

    // Focus on the quantity input
    const qtyInput = batchRow.querySelector('[data-batch-tracker-target="qtyInput"]')
    qtyInput.focus()

    // Auto-save after a short delay
    setTimeout(() => this.saveBatch(batchRow), 1000)
  }

  removeBatch(event) {
    const batchRow = event.target.closest('[data-batch-tracker-target="batchRow"]')
    if (batchRow) {
      batchRow.remove()
      this.checkEmptyState()
      this.saveBatches()
    }
  }

  hideEmptyState() {
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.style.display = 'none'
    }
  }

  checkEmptyState() {
    const hasBatches = this.batchRowTargets.length > 0
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.style.display = hasBatches ? 'none' : 'block'
    }
  }

  saveBatch(batchRow) {
    // Collect data from the batch row
    const batchData = this.extractBatchData(batchRow)

    // Save to localStorage for now (could be enhanced to save to server)
    this.saveBatches()

    // Visual feedback
    this.showSaveIndicator(batchRow)
  }

  extractBatchData(batchRow) {
    return {
      batchNumber: batchRow.querySelector('[data-batch-tracker-target="batchNumber"]').textContent,
      date: batchRow.querySelector('[data-batch-tracker-target="dateInput"]').value,
      time: batchRow.querySelector('[data-batch-tracker-target="timeInput"]').value,
      qty: batchRow.querySelector('[data-batch-tracker-target="qtyInput"]').value,
      operator: batchRow.querySelector('[data-batch-tracker-target="operatorInput"]').value,
      notes: batchRow.querySelector('[data-batch-tracker-target="notesInput"]').value
    }
  }

  saveBatches() {
    const batches = this.batchRowTargets.map(row => this.extractBatchData(row))
    const key = `ecard_batches_${this.worksOrderIdValue}_op_${this.operationPositionValue}`
    localStorage.setItem(key, JSON.stringify(batches))
  }

  loadExistingBatches() {
    const key = `ecard_batches_${this.worksOrderIdValue}_op_${this.operationPositionValue}`
    const savedBatches = localStorage.getItem(key)

    if (savedBatches) {
      const batches = JSON.parse(savedBatches)
      batches.forEach(batch => this.recreateBatch(batch))
    }
  }

  recreateBatch(batchData) {
    this.batchCount++

    const template = this.batchTemplateTarget.content.cloneNode(true)
    const batchRow = template.querySelector('[data-batch-tracker-target="batchRow"]')

    // Populate the fields
    batchRow.querySelector('[data-batch-tracker-target="batchNumber"]').textContent = batchData.batchNumber || `B${this.batchCount}`
    batchRow.querySelector('[data-batch-tracker-target="dateInput"]').value = batchData.date || ''
    batchRow.querySelector('[data-batch-tracker-target="timeInput"]').value = batchData.time || ''
    batchRow.querySelector('[data-batch-tracker-target="qtyInput"]').value = batchData.qty || ''
    batchRow.querySelector('[data-batch-tracker-target="operatorInput"]').value = batchData.operator || ''
    batchRow.querySelector('[data-batch-tracker-target="notesInput"]').value = batchData.notes || ''

    this.hideEmptyState()
    this.batchContainerTarget.appendChild(batchRow)
  }

  showSaveIndicator(batchRow) {
    // Add a subtle flash to indicate save
    batchRow.style.transition = 'background-color 0.3s'
    batchRow.style.backgroundColor = '#f0f9ff'

    setTimeout(() => {
      batchRow.style.backgroundColor = ''
    }, 300)
  }

  // Auto-save on input changes
  handleInput(event) {
    const batchRow = event.target.closest('[data-batch-tracker-target="batchRow"]')
    if (batchRow) {
      clearTimeout(this.saveTimeout)
      this.saveTimeout = setTimeout(() => this.saveBatch(batchRow), 1000)
    }
  }
}
