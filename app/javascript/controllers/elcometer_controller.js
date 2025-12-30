// app/javascript/controllers/elcometer_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "connectButton",
    "stopButton",
    "readingsList",
    "statistics",
    "manualInput",
    "manualReadingInput",
    "readingsData"
  ]

  static values = {
    treatmentId: String,
    processType: String,
    targetThickness: Number,
    displayName: String
  }

  connect() {
    this.readings = []
    this.port = null
    this.reader = null
    this.isReading = false

    // Check if Web Serial API is available
    if (!("serial" in navigator)) {
      this.showError("Web Serial API not supported. Please use Chrome or Edge browser.")
      this.connectButtonTarget.disabled = true
    }

    // Load any existing readings from the hidden field
    this.loadExistingReadings()
  }

  disconnect() {
    this.stopReading()
  }

  async connectElcometer() {
    try {
      // Request the port
      this.port = await navigator.serial.requestPort()

      // Open with settings that work for Elcometer 456
      await this.port.open({
        baudRate: 9600,
        dataBits: 8,
        stopBits: 1,
        parity: "none"
      })

      this.showSuccess("✅ Connected to Elcometer!")
      this.connectButtonTarget.classList.add("hidden")
      this.stopButtonTarget.classList.remove("hidden")

      // Start reading
      this.isReading = true
      this.startReading()

    } catch (err) {
      if (err.name === 'NotFoundError') {
        this.showError("No device selected")
      } else {
        this.showError(`Connection error: ${err.message}`)
      }
      console.error("Elcometer connection error:", err)
    }
  }

  async startReading() {
    try {
      const decoder = new TextDecoderStream()
      this.port.readable.pipeTo(decoder.writable)
      this.reader = decoder.readable.getReader()

      let buffer = ""

      while (this.isReading) {
        const { value, done } = await this.reader.read()
        if (done) break

        // Add to buffer
        buffer += value

        // Process complete lines
        const lines = buffer.split('\n')
        buffer = lines.pop() // Keep incomplete line in buffer

        for (const line of lines) {
          this.processReading(line)
        }
      }
    } catch (err) {
      if (this.isReading) { // Only show error if we didn't intentionally stop
        this.showError(`Reading error: ${err.message}`)
        console.error("Elcometer reading error:", err)
      }
    }
  }

  processReading(line) {
    // Parse format: "    70.7 um   N1    "
    // Extract the number before "um"
    const match = line.match(/\s*([\d.]+)\s*um/i)

    if (match) {
      const reading = parseFloat(match[1])

      if (!isNaN(reading) && reading > 0) {
        this.addReading(reading)
      }
    }
  }

  // Handle Enter key in manual reading input
  // Add readings from the 8 manual input fields
  addManualReadings() {
    if (!this.hasManualReadingInputTarget) return

    const inputs = this.manualReadingInputTargets
    const values = []
    const errors = []

    inputs.forEach((input, index) => {
      const valueStr = input.value.trim()

      if (valueStr) {
        const value = parseFloat(valueStr)
        if (!isNaN(value) && value > 0) {
          values.push(value)
        } else {
          errors.push(`Field ${index + 1}`)
        }
      }
    })

    if (values.length === 0 && errors.length === 0) {
      this.showWarning('Please enter at least one reading')
      return
    }

    // Add all valid readings
    values.forEach(value => this.addReading(value))

    // Clear all inputs
    inputs.forEach(input => input.value = '')

    // Show feedback
    if (values.length > 0) {
      this.showSuccess(`Added ${values.length} reading(s)`)
    }

    if (errors.length > 0) {
      this.showError(`Invalid values in: ${errors.join(', ')}`)
    }

    // Focus first input
    if (inputs.length > 0) {
      inputs[0].focus()
    }
  }

  addReading(value) {
    // Round to 1 decimal place (Elcometer precision)
    const roundedValue = Math.round(value * 10) / 10

    this.readings.push(roundedValue)
    this.updateDisplay()
    this.updateHiddenField()

    // Visual feedback - flash the new reading
    this.flashNewReading()
  }

  updateDisplay() {
    // Update readings list
    const readingsHTML = this.readings.map((reading, index) =>
      `<span class="inline-block px-2 py-1 bg-blue-100 text-blue-800 rounded text-sm mr-2 mb-2">
        ${reading} µm
      </span>`
    ).join('')

    this.readingsListTarget.innerHTML = readingsHTML ||
      '<span class="text-gray-400 text-sm">No readings yet...</span>'

    // Update statistics
    if (this.readings.length > 0) {
      const stats = this.calculateStatistics()
      this.statisticsTarget.innerHTML = `
        <div class="grid grid-cols-4 gap-4 p-3 bg-gray-50 rounded-md">
          <div>
            <div class="text-xs text-gray-500">Count</div>
            <div class="text-lg font-semibold text-gray-900">${stats.count}</div>
          </div>
          <div>
            <div class="text-xs text-gray-500">Mean</div>
            <div class="text-lg font-semibold text-blue-600">${stats.mean} µm</div>
          </div>
          <div>
            <div class="text-xs text-gray-500">Min</div>
            <div class="text-lg font-semibold text-gray-900">${stats.min} µm</div>
          </div>
          <div>
            <div class="text-xs text-gray-500">Max</div>
            <div class="text-lg font-semibold text-gray-900">${stats.max} µm</div>
          </div>
        </div>
      `
    } else {
      this.statisticsTarget.innerHTML = ''
    }
  }

  calculateStatistics() {
    const count = this.readings.length
    const sum = this.readings.reduce((a, b) => a + b, 0)
    const mean = Math.round((sum / count) * 10) / 10
    const min = Math.min(...this.readings)
    const max = Math.max(...this.readings)

    return { count, mean, min, max }
  }

  updateHiddenField() {
    // Store readings in the hidden field for form submission
    if (this.hasReadingsDataTarget) {
      this.readingsDataTarget.value = JSON.stringify(this.readings)
    }
  }

  async stopReading() {
    this.isReading = false

    try {
      if (this.reader) {
        await this.reader.cancel()
        this.reader = null
      }

      if (this.port) {
        await this.port.close()
        this.port = null
      }

      this.showSuccess("Disconnected from Elcometer")
      this.connectButtonTarget.classList.remove("hidden")
      this.stopButtonTarget.classList.add("hidden")

    } catch (err) {
      console.error("Error stopping:", err)
    }
  }

  clearReadings() {
    if (confirm("Clear all readings for this treatment?")) {
      this.readings = []
      this.updateDisplay()
      this.updateHiddenField()
      this.showSuccess("Readings cleared")
    }
  }

  loadExistingReadings() {
    // Load readings from hidden field if editing
    if (this.hasReadingsDataTarget && this.readingsDataTarget.value) {
      try {
        const data = JSON.parse(this.readingsDataTarget.value)
        if (Array.isArray(data) && data.length > 0) {
          this.readings = data
          this.updateDisplay()
        }
      } catch (err) {
        console.error("Error loading existing readings:", err)
      }
    }
  }

  flashNewReading() {
    // Visual feedback - briefly highlight statistics
    if (this.hasStatisticsTarget) {
      this.statisticsTarget.classList.add("ring-2", "ring-blue-400")
      setTimeout(() => {
        this.statisticsTarget.classList.remove("ring-2", "ring-blue-400")
      }, 300)
    }
  }

  showSuccess(message) {
    this.showNotification(message, "success")
  }

  showError(message) {
    this.showNotification(message, "error")
  }

  showWarning(message) {
    this.showNotification(message, "warning")
  }

  showNotification(message, type) {
    // Find or create notification container
    let container = document.getElementById("elcometer-notifications")
    if (!container) {
      container = document.createElement("div")
      container.id = "elcometer-notifications"
      container.className = "fixed top-4 right-4 z-50 space-y-2"
      document.body.appendChild(container)
    }

    // Color scheme based on type
    const colors = {
      success: "bg-green-50 border-green-200 text-green-800",
      error: "bg-red-50 border-red-200 text-red-800",
      warning: "bg-amber-50 border-amber-200 text-amber-800"
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

    // Auto-remove after 5 seconds
    setTimeout(() => {
      notification.remove()
    }, 5000)
  }
}
