// app/javascript/controllers/enp_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "startInput",
    "finishInput",
    "growthDisplay",
    "statistics",
    "progressCounter",
    "measurementsData"
  ]

  static values = {
    treatmentId: String,
    processType: String,
    enpType: String,
    displayName: String
  }

  connect() {
    this.measurements = this.initializeMeasurements()
    this.loadExistingMeasurements()
    this.updateDisplay()
  }

  initializeMeasurements() {
    return [
      { point: "A", start_mm: null, finish_mm: null, growth_um: null },
      { point: "B", start_mm: null, finish_mm: null, growth_um: null },
      { point: "C", start_mm: null, finish_mm: null, growth_um: null },
      { point: "D", start_mm: null, finish_mm: null, growth_um: null },
      { point: "E", start_mm: null, finish_mm: null, growth_um: null },
      { point: "F", start_mm: null, finish_mm: null, growth_um: null }
    ]
  }

  // Handle input changes - triggered on blur
  updateMeasurement(event) {
    const input = event.target
    const index = parseInt(input.dataset.index)
    const field = input.dataset.field // 'start' or 'finish'
    const value = parseFloat(input.value)

    // Update the measurement
    if (!isNaN(value) && value > 0) {
      if (field === 'start') {
        this.measurements[index].start_mm = value
      } else if (field === 'finish') {
        this.measurements[index].finish_mm = value
      }

      // Calculate growth
      this.calculateGrowth(index)
    } else if (input.value.trim() === '') {
      // Clear the field if empty
      if (field === 'start') {
        this.measurements[index].start_mm = null
      } else if (field === 'finish') {
        this.measurements[index].finish_mm = null
      }
      this.measurements[index].growth_um = null
    }

    this.updateDisplay()
    this.updateHiddenField()
  }

  calculateGrowth(index) {
    const measurement = this.measurements[index]

    if (measurement.start_mm !== null && measurement.finish_mm !== null) {
      // Growth in µm = (finish - start) × 1000
      const growthMm = measurement.finish_mm - measurement.start_mm
      measurement.growth_um = Math.round(growthMm * 1000 * 10) / 10 // Round to 1 decimal
    } else {
      measurement.growth_um = null
    }
  }

  updateDisplay() {
    // Update growth displays and validation styling
    this.measurements.forEach((measurement, index) => {
      const growthCell = this.growthDisplayTargets[index]

      if (measurement.growth_um !== null) {
        growthCell.textContent = `${measurement.growth_um} µm`

        // Visual validation - red for negative growth
        if (measurement.growth_um < 0) {
          growthCell.classList.add('text-red-600', 'font-semibold')
          growthCell.classList.remove('text-green-600')
        } else {
          growthCell.classList.add('text-green-600')
          growthCell.classList.remove('text-red-600', 'font-semibold')
        }
      } else {
        growthCell.textContent = '—'
        growthCell.classList.remove('text-red-600', 'text-green-600', 'font-semibold')
      }
    })

    // Update statistics
    this.updateStatistics()

    // Update progress counter
    this.updateProgress()
  }

  updateStatistics() {
    const validGrowths = this.measurements
      .map(m => m.growth_um)
      .filter(g => g !== null && g >= 0) // Exclude null and negative values

    if (validGrowths.length > 0) {
      const mean = validGrowths.reduce((a, b) => a + b, 0) / validGrowths.length
      const min = Math.min(...validGrowths)
      const max = Math.max(...validGrowths)

      this.statisticsTarget.innerHTML = `
        <div class="grid grid-cols-4 gap-4 p-3 bg-gray-50 rounded-md">
          <div>
            <div class="text-xs text-gray-500">Valid Points</div>
            <div class="text-lg font-semibold text-gray-900">${validGrowths.length}/6</div>
          </div>
          <div>
            <div class="text-xs text-gray-500">Mean Growth</div>
            <div class="text-lg font-semibold text-blue-600">${Math.round(mean * 10) / 10} µm</div>
          </div>
          <div>
            <div class="text-xs text-gray-500">Min Growth</div>
            <div class="text-lg font-semibold text-gray-900">${min} µm</div>
          </div>
          <div>
            <div class="text-xs text-gray-500">Max Growth</div>
            <div class="text-lg font-semibold text-gray-900">${max} µm</div>
          </div>
        </div>
      `
    } else {
      this.statisticsTarget.innerHTML = ''
    }
  }

  updateProgress() {
    const completeCount = this.measurements.filter(m =>
      m.start_mm !== null && m.finish_mm !== null && m.growth_um !== null
    ).length

    if (this.hasProgressCounterTarget) {
      this.progressCounterTarget.textContent = `${completeCount}/6 complete`

      // Color based on completion
      if (completeCount === 6) {
        this.progressCounterTarget.classList.add('text-green-600', 'font-semibold')
        this.progressCounterTarget.classList.remove('text-gray-500')
      } else if (completeCount > 0) {
        this.progressCounterTarget.classList.add('text-blue-600')
        this.progressCounterTarget.classList.remove('text-gray-500', 'text-green-600', 'font-semibold')
      } else {
        this.progressCounterTarget.classList.add('text-gray-500')
        this.progressCounterTarget.classList.remove('text-blue-600', 'text-green-600', 'font-semibold')
      }
    }
  }

  updateHiddenField() {
    if (this.hasMeasurementsDataTarget) {
      // Only include measurements with at least one value
      const dataToStore = this.measurements.filter(m =>
        m.start_mm !== null || m.finish_mm !== null || m.growth_um !== null
      )

      this.measurementsDataTarget.value = JSON.stringify(dataToStore)
    }
  }

  clearAllMeasurements() {
    if (confirm("Clear all ENP measurements for this treatment?")) {
      this.measurements = this.initializeMeasurements()

      // Clear all input fields
      this.startInputTargets.forEach(input => input.value = '')
      this.finishInputTargets.forEach(input => input.value = '')

      this.updateDisplay()
      this.updateHiddenField()
      this.showSuccess("ENP measurements cleared")
    }
  }

  loadExistingMeasurements() {
    if (this.hasMeasurementsDataTarget && this.measurementsDataTarget.value) {
      try {
        const data = JSON.parse(this.measurementsDataTarget.value)
        if (Array.isArray(data)) {
          // Merge existing data with initialized structure
          data.forEach(existing => {
            const index = this.measurements.findIndex(m => m.point === existing.point)
            if (index !== -1) {
              this.measurements[index] = { ...existing }

              // Populate input fields
              if (existing.start_mm !== null) {
                this.startInputTargets[index].value = existing.start_mm
              }
              if (existing.finish_mm !== null) {
                this.finishInputTargets[index].value = existing.finish_mm
              }
            }
          })
        }
      } catch (err) {
        console.error("Error loading existing ENP measurements:", err)
      }
    }
  }

  showSuccess(message) {
    this.showNotification(message, "success")
  }

  showError(message) {
    this.showNotification(message, "error")
  }

  showNotification(message, type) {
    let container = document.getElementById("enp-notifications")
    if (!container) {
      container = document.createElement("div")
      container.id = "enp-notifications"
      container.className = "fixed top-4 right-4 z-50 space-y-2"
      document.body.appendChild(container)
    }

    const colors = {
      success: "bg-green-50 border-green-200 text-green-800",
      error: "bg-red-50 border-red-200 text-red-800"
    }

    const notification = document.createElement("div")
    notification.className = `${colors[type]} border rounded-md p-3 shadow-lg max-w-sm animate-fade-in`
    notification.innerHTML = `
      <div class="flex items-start">
        <div class="flex-1 text-sm">${message}</div>
        <button class="ml-3 text-gray-400 hover:text-gray-600" onclick="this.parentElement.parentElement.remove()">
          <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"/>
          </svg>
        </button>
      </div>
    `

    container.appendChild(notification)

    setTimeout(() => {
      notification.remove()
    }, 5000)
  }
}
