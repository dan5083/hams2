// app/javascript/controllers/ppi_form/operation_selection_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["selectedOperationsField", "selectedContainer"]
  static outlets = ["operations-filter", "treatment-selection"]

  static values = {
    previewPath: String,
    csrfToken: String,
    maxOperations: { type: Number, default: 3 }
  }

  connect() {
    this.selectedOperations = []
    this.initializeExistingData()

    // Listen for operation selection events from operations filter controller
    this.element.addEventListener("operations-filter:operationSelected", (event) => {
      this.handleOperationSelected(event.detail)
    })
  }

  initializeExistingData() {
    try {
      const existingData = JSON.parse(this.selectedOperationsFieldTarget.value || '[]')
      this.selectedOperations = existingData
      this.updateSelectedOperations()
    } catch(e) {
      console.error("Error parsing existing operations:", e)
      this.selectedOperations = []
    }
  }

  handleOperationSelected(detail) {
    const { operationId, element } = detail
    this.selectOperation(operationId, element)
  }

  selectOperation(operationId, element) {
    if (this.selectedOperations.includes(operationId)) return

    if (this.selectedOperations.length >= this.maxOperationsValue) {
      alert(`Maximum ${this.maxOperationsValue} operations allowed`)
      return
    }

    this.selectedOperations.push(operationId)
    this.updateSelectedOperations()

    if (element) {
      element.classList.add('opacity-50')
    }

    // Notify operations filter to update all selection states
    if (this.hasOperationsFilterOutlet) {
      this.operationsFilterOutlet.refreshSelectionStates()
    }
  }

  removeOperation(event) {
    const operationId = event.params.operationId
    this.selectedOperations = this.selectedOperations.filter(id => id !== operationId)
    this.updateSelectedOperations()

    // Remove opacity from all matching elements
    this.element.querySelectorAll(`[data-operation-id="${operationId}"]`).forEach(el => {
      el.classList.remove('opacity-50')
    })

    // Notify operations filter to update selection states
    if (this.hasOperationsFilterOutlet) {
      this.operationsFilterOutlet.refreshSelectionStates()
    }
  }

  async updateSelectedOperations() {
    this.selectedOperationsFieldTarget.value = JSON.stringify(this.selectedOperations)

    if (this.selectedOperations.length === 0) {
      this.selectedContainerTarget.innerHTML = '<p class="text-gray-500 text-sm">No treatments selected</p>'
      return
    }

    try {
      const requestData = { operation_ids: this.selectedOperations }

      // Add thickness for ENP interpolation if available
      if (this.hasTreatmentSelectionOutlet) {
        const thickness = this.treatmentSelectionOutlet.getENPThickness()
        if (thickness && thickness > 0) {
          requestData.target_thickness = thickness
        }
      }

      const response = await fetch(this.previewPathValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfTokenValue
        },
        body: JSON.stringify(requestData)
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const data = await response.json()
      const operations = data.operations || []

      this.selectedContainerTarget.innerHTML = operations.map((op, index) => {
        const isAutoInserted = op.auto_inserted
        const bgColor = isAutoInserted ? 'bg-gray-100 border border-gray-300' : 'bg-blue-100 border border-blue-300'
        const textColor = isAutoInserted ? 'italic text-gray-600' : 'text-gray-900'
        const autoLabel = isAutoInserted ? '<span class="text-xs text-gray-500 ml-2">(auto-inserted)</span>' : ''
        const removeButton = isAutoInserted ? '' :
          `<button type="button" class="text-red-600 hover:text-red-800 ml-2" data-action="click->operation-selection#removeOperation" data-operation-selection-operation-id-param="${op.id}">×</button>`

        return `
          <div class="${bgColor} rounded px-3 py-2 flex justify-between items-center" data-operation-id="${op.id}">
            <span class="text-sm ${textColor}">
              <strong>${index + 1}.</strong>
              ${op.display_name}: ${op.operation_text}
              ${autoLabel}
            </span>
            ${removeButton}
          </div>
        `
      }).join('')
    } catch (error) {
      console.error('Error updating selected operations:', error)
      this.selectedContainerTarget.innerHTML = '<p class="text-red-500 text-sm">Error loading operation preview</p>'
    }
  }

  // Public method for other controllers
  getSelectedOperations() {
    return [...this.selectedOperations]
  }

  // Check if any ENP operations are selected
  hasENPOperations() {
    return this.selectedOperations.some(id =>
      id.includes('PHOS') || id.includes('PTFE') || id.includes('NICKLAD') || id.includes('VANDALLOY')
    )
  }

  // Method to refresh preview when external changes occur (like ENP thickness)
  refreshPreview() {
    if (this.selectedOperations.length > 0) {
      this.updateSelectedOperations()
    }
  }
}
