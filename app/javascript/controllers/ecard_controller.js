// app/javascript/controllers/ecard_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["header", "operations", "footer"]
  static values = {
    worksOrderId: String,
    totalOperations: Number,
    autoRefresh: Boolean
  }

  connect() {
    this.setupEventListeners()
    this.initializeAutoRefresh()
    this.loadInitialState()
  }

  disconnect() {
    this.cleanup()
  }

  setupEventListeners() {
    // Listen for operation sign-off events from child controllers
    this.element.addEventListener('ecard:operationSignedOff', (event) => {
      this.handleOperationSignedOff(event.detail)
    })

    // Listen for batch updates from batch tracker controllers
    this.element.addEventListener('ecard:batchUpdated', (event) => {
      this.handleBatchUpdated(event.detail)
    })

    // Listen for quantity releases
    this.element.addEventListener('ecard:quantityReleased', (event) => {
      this.handleQuantityReleased(event.detail)
    })
  }

  loadInitialState() {
    // Sync initial state between all child controllers
    this.syncComponentStates()

    // Check if any operations are already signed off
    this.updateCompletionStatus()
  }

  initializeAutoRefresh() {
    if (this.autoRefreshValue) {
      // Refresh every 2 minutes
      this.refreshInterval = setInterval(() => {
        this.refreshECard()
      }, 120000)
    }
  }

  cleanup() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval)
    }
  }

  // Handle operation sign-off events
  handleOperationSignedOff(detail) {
    const { operationPosition, operationName } = detail

    console.log(`Operation ${operationPosition} (${operationName}) signed off`)

    // Notify header to update progress
    this.notifyHeaderController('operationCompleted')

    // Notify footer to update progress
    this.notifyFooterController('operationCompleted')

    // Update overall completion status
    this.updateCompletionStatus()

    // Show success notification
    this.showNotification(`✅ Operation ${operationPosition} signed off successfully`, 'success')

    // Optional: Auto-scroll to next incomplete operation
    this.scrollToNextOperation()
  }

  // Handle batch data updates
  handleBatchUpdated(detail) {
    const { operationPosition, totalQuantity, batchCount } = detail

    // Could sync batch data with server here
    this.syncBatchData(operationPosition, detail)
  }

  // Handle quantity release events
  handleQuantityReleased(detail) {
    const { quantity } = detail

    // Notify footer to update release status
    this.notifyFooterController('quantityReleased', quantity)
  }

  // Notify child controllers of events
  notifyHeaderController(method, data = null) {
    const headerElement = this.hasHeaderTarget ? this.headerTarget :
                         this.element.querySelector('[data-controller*="ecard-header"]')

    if (headerElement) {
      const controller = this.application.getControllerForElementAndIdentifier(
        headerElement, 'ecard-header'
      )
      if (controller && typeof controller[method] === 'function') {
        controller[method](data)
      }
    }
  }

  notifyFooterController(method, data = null) {
    const footerElement = this.hasFooterTarget ? this.footerTarget :
                         this.element.querySelector('[data-controller*="ecard-footer"]')

    if (footerElement) {
      const controller = this.application.getControllerForElementAndIdentifier(
        footerElement, 'ecard-footer'
      )
      if (controller && typeof controller[method] === 'function') {
        controller[method](data)
      }
    }
  }

  // Update completion status across all components
  updateCompletionStatus() {
    const operationElements = this.element.querySelectorAll('[data-controller*="ecard-operation"]')
    let completedCount = 0

    operationElements.forEach(element => {
      const controller = this.application.getControllerForElementAndIdentifier(
        element, 'ecard-operation'
      )
      if (controller && controller.signedOffValue) {
        completedCount++
      }
    })

    // Update completion percentage
    const completionPercentage = operationElements.length > 0 ?
      (completedCount / operationElements.length) * 100 : 0

    // Store for use by child controllers
    this.element.dataset.completionPercentage = completionPercentage.toFixed(1)
    this.element.dataset.completedOperations = completedCount

    // Check if work order is complete
    if (completedCount === operationElements.length && operationElements.length > 0) {
      this.handleWorkOrderComplete()
    }
  }

  // Handle work order completion
  handleWorkOrderComplete() {
    this.showNotification('🎉 All operations completed! Work order ready for release.', 'success')

    // Optional: Auto-scroll to footer for release actions
    this.scrollToFooter()

    // Could trigger server notification or workflow here
    this.notifyWorkOrderComplete()
  }

  // Scroll to next incomplete operation
  scrollToNextOperation() {
    const operationElements = this.element.querySelectorAll('[data-controller*="ecard-operation"]')

    for (let element of operationElements) {
      const controller = this.application.getControllerForElementAndIdentifier(
        element, 'ecard-operation'
      )
      if (controller && !controller.signedOffValue) {
        element.scrollIntoView({
          behavior: 'smooth',
          block: 'center'
        })
        break
      }
    }
  }

  // Scroll to footer
  scrollToFooter() {
    if (this.hasFooterTarget) {
      this.footerTarget.scrollIntoView({
        behavior: 'smooth',
        block: 'center'
      })
    }
  }

  // Sync states between components
  syncComponentStates() {
    // Ensure all child controllers have consistent data
    const sharedData = {
      worksOrderId: this.worksOrderIdValue,
      totalOperations: this.totalOperationsValue
    }

    // Could dispatch custom events with shared data
    this.element.dispatchEvent(new CustomEvent('ecard:stateSync', {
      detail: sharedData,
      bubbles: true
    }))
  }

  // Refresh the entire e-card (could fetch from server)
  async refreshECard() {
    try {
      // Show loading state
      this.setLoadingState(true)

      // In a full implementation, this might fetch updated data from the server
      // For now, just refresh component states
      this.updateCompletionStatus()
      this.syncComponentStates()

      // Notify all child controllers to refresh
      this.notifyHeaderController('refreshData')
      this.notifyFooterController('refreshData')

      this.showNotification('E-Card refreshed', 'info')

    } catch (error) {
      console.error('Failed to refresh e-card:', error)
      this.showNotification('Failed to refresh e-card', 'error')
    } finally {
      this.setLoadingState(false)
    }
  }

  // Set loading state for the entire e-card
  setLoadingState(isLoading) {
    if (isLoading) {
      this.element.classList.add('opacity-75', 'pointer-events-none')
    } else {
      this.element.classList.remove('opacity-75', 'pointer-events-none')
    }
  }

  // Show notifications to user
  showNotification(message, type = 'info') {
    // Create a simple notification
    const notification = document.createElement('div')
    notification.className = `fixed top-4 right-4 px-4 py-2 rounded shadow-lg z-50 transition-all duration-300 ${this.getNotificationClasses(type)}`
    notification.textContent = message

    document.body.appendChild(notification)

    // Auto-remove after 3 seconds
    setTimeout(() => {
      notification.classList.add('opacity-0', 'translate-x-full')
      setTimeout(() => {
        document.body.removeChild(notification)
      }, 300)
    }, 3000)
  }

  getNotificationClasses(type) {
    switch (type) {
      case 'success':
        return 'bg-green-500 text-white'
      case 'error':
        return 'bg-red-500 text-white'
      case 'warning':
        return 'bg-yellow-500 text-black'
      default:
        return 'bg-blue-500 text-white'
    }
  }

  // Sync batch data with server (placeholder)
  async syncBatchData(operationPosition, batchData) {
    try {
      // In a full implementation, this would save to server
      console.log(`Syncing batch data for operation ${operationPosition}:`, batchData)

      // Could make AJAX call to save batch data
      // await this.saveBatchData(operationPosition, batchData)

    } catch (error) {
      console.error('Failed to sync batch data:', error)
    }
  }

  // Notify server of work order completion (placeholder)
  async notifyWorkOrderComplete() {
    try {
      console.log(`Work order ${this.worksOrderIdValue} completed`)

      // Could trigger server-side workflows:
      // - Generate completion notifications
      // - Update work order status
      // - Trigger quality checks
      // - etc.

    } catch (error) {
      console.error('Failed to notify work order completion:', error)
    }
  }

  // Manual refresh triggered by user
  manualRefresh() {
    this.refreshECard()
  }

  // Export e-card data (placeholder for future functionality)
  exportData() {
    const data = {
      worksOrderId: this.worksOrderIdValue,
      completionStatus: this.element.dataset.completionPercentage,
      exportedAt: new Date().toISOString()
    }

    console.log('Export data:', data)
    // Could trigger download or send to server
  }
}
