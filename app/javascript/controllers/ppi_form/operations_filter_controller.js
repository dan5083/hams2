// app/javascript/controllers/ppi_form/operations_filter_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    filterPath: String,
    csrfToken: String
  }

  static outlets = ["operation-selection"]

  connect() {
    // Listen for treatment changes from treatment selection controller
    this.element.addEventListener("treatment-selection:treatmentChanged", (event) => {
      this.handleTreatmentChanged(event.detail)
    })
  }

  async handleTreatmentChanged(detail) {
    const { criteria, activeTreatments } = detail

    // Load operations for each active treatment
    for (const criteriaData of criteria) {
      await this.loadOperationsForTreatment(criteriaData)
    }
  }

  async loadOperationsForTreatment({ treatment, treatmentIndex, criteria }) {
    const operationsList = this.element.querySelector(`.operations-list[data-treatment="${treatment}"][data-treatment-index="${treatmentIndex}"]`)

    if (!operationsList) return

    try {
      // Special handling for different treatment types
      if (treatment === 'chemical_conversion') {
        await this.loadChemicalConversionOperations(operationsList)
      } else if (!this.hasCriteria(criteria, treatment)) {
        operationsList.innerHTML = '<p class="text-gray-500 text-xs">Select criteria above to see operations</p>'
      } else {
        const operations = await this.fetchOperations(criteria)
        this.displayOperationsInContainer(operations, operationsList, treatment)
      }
    } catch (error) {
      console.error(`Error loading operations for ${treatment}:`, error)
      operationsList.innerHTML = '<p class="text-red-500 text-xs">Error loading operations</p>'
    }
  }

  async loadChemicalConversionOperations(container) {
    try {
      const operations = await this.fetchOperations({ anodising_types: ['chemical_conversion'] })
      this.displayOperationsInContainer(operations, container, 'chemical_conversion')
    } catch (error) {
      console.error('Error loading chemical conversion operations:', error)
      container.innerHTML = '<p class="text-red-500 text-xs">Error loading operations</p>'
    }
  }

  async fetchOperations(criteria) {
    const response = await fetch(this.filterPathValue, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.csrfTokenValue
      },
      body: JSON.stringify(criteria)
    })

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`)
    }

    return await response.json()
  }

  displayOperationsInContainer(operations, container, treatment) {
    if (operations.length === 0) {
      container.innerHTML = '<p class="text-gray-500 text-xs">No matching operations found</p>'
      return
    }

    container.innerHTML = operations.map(op => {
      const displayText = (treatment === 'chemical_conversion' || treatment === 'electroless_nickel_plating') ?
        op.id.replace(/_/g, ' ') : op.display_name

      return `
        <div class="operation-item bg-white border border-gray-200 rounded px-2 py-1 cursor-pointer hover:bg-gray-50 text-xs"
             data-operation-id="${op.id}"
             data-action="click->operations-filter#selectOperation">
          <div class="flex justify-between items-center">
            <span class="font-medium">${displayText}</span>
            <button type="button" class="text-green-600 hover:text-green-800">+</button>
          </div>
          <p class="text-gray-600 mt-1">${op.operation_text}</p>
          ${op.specifications ? `<p class="text-purple-600 text-xs mt-1">${op.specifications}</p>` : ''}
        </div>
      `
    }).join('')

    // Update selection states
    this.updateSelectionStates(container)
  }

  selectOperation(event) {
    const element = event.currentTarget
    const operationId = element.dataset.operationId

    // Dispatch event to operation selection controller
    this.dispatch("operationSelected", {
      detail: { operationId, element }
    })
  }

  updateSelectionStates(container) {
    // Get selected operations from operation selection controller
    if (this.hasOperationSelectionOutlet) {
      const selectedOperations = this.operationSelectionOutlet.getSelectedOperations()

      container.querySelectorAll('.operation-item').forEach(item => {
        const operationId = item.dataset.operationId
        if (selectedOperations.includes(operationId)) {
          item.classList.add('opacity-50')
        } else {
          item.classList.remove('opacity-50')
        }
      })
    }
  }

  // Update all containers when selections change
  refreshSelectionStates() {
    this.element.querySelectorAll('.operations-list').forEach(container => {
      this.updateSelectionStates(container)
    })
  }

  hasCriteria(criteria, treatment) {
    if (treatment === 'electroless_nickel_plating' || treatment === 'chemical_conversion') {
      return true // Always load these operations
    }
    return criteria.alloys?.length || criteria.target_thicknesses?.length || criteria.anodic_classes?.length
  }
}
