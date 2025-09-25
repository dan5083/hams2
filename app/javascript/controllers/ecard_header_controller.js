// app/javascript/controllers/ecard_header_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["progressBar", "statusIndicator"]
  static values = {
    worksOrderId: String,
    totalOperations: Number,
    completedOperations: Number
  }

  connect() {
    this.updateProgressDisplay()
    this.setupAutoRefresh()
  }

  disconnect() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
    }
  }

  updateProgressDisplay() {
    if (this.hasProgressBarTarget && this.totalOperationsValue > 0) {
      const percentage = (this.completedOperationsValue / this.totalOperationsValue) * 100
      this.progressBarTarget.style.width = `${percentage}%`
    }
  }

  setupAutoRefresh() {
    // Refresh header data every 30 seconds to show updated progress
    this.refreshTimer = setInterval(() => {
      this.refreshStatus()
    }, 30000)
  }

  async refreshStatus() {
    try {
      // Could fetch updated status from server
      // For now, just update timestamp
      this.updateTimestamp()
    } catch (error) {
      console.warn('Failed to refresh e-card header status:', error)
    }
  }

  updateTimestamp() {
    const timestampElement = this.element.querySelector('[data-timestamp]')
    if (timestampElement) {
      timestampElement.textContent = new Date().toLocaleString('en-GB', {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      })
    }
  }

  // Method to be called when operations are signed off
  operationCompleted() {
    this.completedOperationsValue += 1
    this.updateProgressDisplay()
  }
}
