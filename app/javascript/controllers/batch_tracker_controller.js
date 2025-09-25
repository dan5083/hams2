// app/javascript/controllers/batch_tracker_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "totalQty"]
  static values = { operationPosition: Number }

  connect() {
    this.batchCounter = 0
  }

  addBatch() {
    this.batchCounter++

    // Remove empty state message if it exists
    const emptyState = this.containerTarget.querySelector('.italic')
    if (emptyState) {
      emptyState.remove()
    }

    const batchNumber = this.batchCounter
    const now = new Date()
    const dateStr = now.toISOString().split('T')[0]
    const timeStr = now.toTimeString().slice(0, 5)

    const batchRow = document.createElement('div')
    batchRow.className = 'grid grid-cols-6 gap-2 items-center'
    batchRow.innerHTML = `
      <div class="text-sm font-medium">B${batchNumber}</div>
      <input type="date" class="text-xs border border-gray-300 rounded px-1 py-1" value="${dateStr}">
      <input type="time" class="text-xs border border-gray-300 rounded px-1 py-1" value="${timeStr}">
      <input type="number" class="text-xs border border-gray-300 rounded px-1 py-1 batch-qty"
             placeholder="Qty" data-action="input->batch-tracker#updateTotal">
      <input type="text" class="text-xs border border-gray-300 rounded px-1 py-1" placeholder="Operator">
      <input type="text" class="text-xs border border-gray-300 rounded px-1 py-1" placeholder="Notes">
    `

    this.containerTarget.appendChild(batchRow)
  }

  updateTotal() {
    const qtyInputs = this.containerTarget.querySelectorAll('.batch-qty')
    let total = 0

    qtyInputs.forEach(input => {
      const value = parseInt(input.value) || 0
      total += value
    })

    if (this.hasTotalQtyTarget) {
      this.totalQtyTarget.value = total
    }
  }
}
