// app/javascript/controllers/ecard_footer_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "progressSummary",
    "qualityStatus",
    "releaseStatus",
    "lastUpdated"
  ]

  static values = {
    worksOrderId: String,
    totalOperations: Number,
    completedOperations: Number,
    totalQuantity: Number,
    releasedQuantity: Number
  }

  connect() {
    this.updateSummary()
    this.setupAutoRefresh()
  }

  disconnect() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
    }
  }

  updateSummary() {
    this.updateProgressSummary()
    this.updateQualityStatus()
    this.updateReleaseStatus()
    this.updateTimestamp()
  }

  updateProgressSummary() {
    if (this.hasProgressSummaryTarget) {
      const percentage = this.totalOperationsValue > 0
        ? ((this.completedOperationsValue / this.totalOperationsValue) * 100).toFixed(1)
        : 0

      const progressText = `${this.completedOperationsValue}/${this.totalOperationsValue} Operations`
      const percentageText = `${percentage}% Complete`

      // Update progress text
      const progressElement = this.progressSummaryTarget.querySelector('[data-progress-text]')
      if (progressElement) {
        progressElement.textContent = progressText
      }

      const percentageElement = this.progressSummaryTarget.querySelector('[data-percentage-text]')
      if (percentageElement) {
        percentageElement.textContent = percentageText
      }

      // Update color based on completion
      this.updateProgressColor(percentage)
    }
  }

  updateProgressColor(percentage) {
    const progressContainer = this.progressSummaryTarget

    // Remove existing color classes
    progressContainer.classList.remove('bg-red-50', 'border-red-200', 'bg-yellow-50', 'border-yellow-200', 'bg-green-50', 'border-green-200')

    const progressText = progressContainer.querySelector('[data-progress-text]')
    const percentageText = progressContainer.querySelector('[data-percentage-text]')

    if (progressText && percentageText) {
      progressText.classList.remove('text-red-600', 'text-yellow-600', 'text-green-600')
      percentageText.classList.remove('text-red-600', 'text-yellow-600', 'text-green-600')
    }

    // Apply new colors based on percentage
    if (percentage >= 100) {
      progressContainer.classList.add('bg-green-50', 'border-green-200')
      if (progressText && percentageText) {
        progressText.classList.add('text-green-600')
        percentageText.classList.add('text-green-600')
      }
    } else if (percentage >= 50) {
      progressContainer.classList.add('bg-yellow-50', 'border-yellow-200')
      if (progressText && percentageText) {
        progressText.classList.add('text-yellow-600')
        percentageText.classList.add('text-yellow-600')
      }
    } else {
      progressContainer.classList.add('bg-red-50', 'border-red-200')
      if (progressText && percentageText) {
        progressText.classList.add('text-red-600')
        percentageText.classList.add('text-red-600')
      }
    }
  }

  updateQualityStatus() {
    if (this.hasQualityStatusTarget) {
      // This could be enhanced to check for actual quality issues
      // For now, show static "No Issues" status
      const statusElement = this.qualityStatusTarget.querySelector('[data-quality-text]')
      const detailElement = this.qualityStatusTarget.querySelector('[data-quality-detail]')

      if (statusElement) statusElement.textContent = "No Issues"
      if (detailElement) detailElement.textContent = "All clear"
    }
  }

  updateReleaseStatus() {
    if (this.hasReleaseStatusTarget) {
      const remainingQuantity = this.totalQuantityValue - this.releasedQuantityValue

      const statusText = `${this.releasedQuantityValue}/${this.totalQuantityValue}`
      const detailText = `${remainingQuantity} remaining`

      const statusElement = this.releaseStatusTarget.querySelector('[data-release-text]')
      const detailElement = this.releaseStatusTarget.querySelector('[data-release-detail]')

      if (statusElement) statusElement.textContent = statusText
      if (detailElement) detailElement.textContent = detailText

      // Update color based on release progress
      this.updateReleaseColor()
    }
  }

  updateReleaseColor() {
    const isFullyReleased = this.releasedQuantityValue >= this.totalQuantityValue
    const releaseContainer = this.releaseStatusTarget

    // Remove existing classes
    releaseContainer.classList.remove('bg-yellow-50', 'border-yellow-200', 'bg-green-50', 'border-green-200')

    const statusText = releaseContainer.querySelector('[data-release-text]')
    const detailText = releaseContainer.querySelector('[data-release-detail]')

    if (statusText && detailText) {
      statusText.classList.remove('text-yellow-600', 'text-green-600')
      detailText.classList.remove('text-yellow-600', 'text-green-600')
    }

    if (isFullyReleased) {
      releaseContainer.classList.add('bg-green-50', 'border-green-200')
      if (statusText && detailText) {
        statusText.classList.add('text-green-600')
        detailText.classList.add('text-green-600')
      }
    } else {
      releaseContainer.classList.add('bg-yellow-50', 'border-yellow-200')
      if (statusText && detailText) {
        statusText.classList.add('text-yellow-600')
        detailText.classList.add('text-yellow-600')
      }
    }
  }

  updateTimestamp() {
    if (this.hasLastUpdatedTarget) {
      const now = new Date()
      const timestamp = now.toLocaleString('en-GB', {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      })
      this.lastUpdatedTarget.textContent = `Last updated: ${timestamp}`
    }
  }

  setupAutoRefresh() {
    // Refresh summary every 60 seconds
    this.refreshTimer = setInterval(() => {
      this.updateTimestamp()
      // Could also fetch updated data from server here
    }, 60000)
  }

  // Method to be called when operations are completed
  operationCompleted() {
    this.completedOperationsValue += 1
    this.updateProgressSummary()
  }

  // Method to be called when quantities are released
  quantityReleased(amount) {
    this.releasedQuantityValue += amount
    this.updateReleaseStatus()
  }

  // Refresh all data (could be triggered by external events)
  refreshData() {
    this.updateSummary()
  }
}
