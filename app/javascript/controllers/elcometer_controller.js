// app/javascript/controllers/elcometer_controller.js
//
// Standard anodic batch (8 readings per batch). No longer owns the serial port.
// It registers as a "sink" with the shared elcometer-session controller, which
// owns the single connection and routes readings here. Manual entry, stats, and
// persistence remain local to the batch.

import { Controller } from "@hotwired/stimulus"

const TARGET_READINGS = 8

export default class extends Controller {
  static targets = ["readingsList", "statistics", "manualReadingInput", "readingsData"]

  static values = {
    treatmentId: String,
    processType: String,
    targetThickness: Number,
    displayName: String
  }

  connect() {
    this.readings = []
    this.session = null

    this.loadExistingReadings()
    this.registerWithSession()

    // Focusing anywhere in this batch makes it the active target for readings.
    this._onFocus = () => this.session && this.session.setPreferred(this)
    this.element.addEventListener("focusin", this._onFocus)
  }

  disconnect() {
    this.element.removeEventListener("focusin", this._onFocus)
    if (this.session) this.session.removeSink(this)
    const el = this.sessionEl
    if (el && el._elcometerPendingSinks) {
      el._elcometerPendingSinks = el._elcometerPendingSinks.filter((s) => s !== this)
    }
  }

  registerWithSession() {
    const el = this.element.closest('[data-controller~="elcometer-session"]')
    this.sessionEl = el
    if (!el) return
    if (el.elcometerSession) {
      el.elcometerSession.addSink(this)
    } else {
      (el._elcometerPendingSinks ||= []).push(this)
    }
  }

  // ── Sink interface (called by the session) ───────────────────────────────

  // Visible? A hidden batch (batch count reduced) must not receive readings.
  isActive() { return this.element.offsetParent !== null }

  sinkLabel() { return this.displayNameValue || "Anodic" }

  acceptsReadings() { return this.isActive() && this.readings.length < TARGET_READINGS }

  isComplete() { return this.readings.length >= TARGET_READINGS }

  progress() {
    return this.isActive()
      ? { done: this.readings.length, expected: TARGET_READINGS }
      : { done: 0, expected: 0 }
  }

  nextSlotLabel() {
    return `reading ${Math.min(this.readings.length + 1, TARGET_READINGS)}/${TARGET_READINGS}`
  }

  // Returns true if the reading was placed.
  acceptReading(value) {
    if (!this.acceptsReadings()) return false
    this.addReading(value, true)
    return true
  }

  // ── Manual entry ──────────────────────────────────────────────────────────

  addManualReading(event) {
    const input = event.target
    const valueStr = input.value.trim()
    if (!valueStr) return

    const value = parseFloat(valueStr)
    if (isNaN(value) || value <= 0) {
      input.value = ""
      return
    }

    this.addReading(value, false)
    input.value = ""
  }

  addReading(value, flash) {
    const rounded = Math.round(value * 10) / 10
    this.readings.push(rounded)
    this.updateDisplay()
    this.updateHiddenField()
    if (flash) this.flash()
    if (this.session) this.session.refresh()
  }

  updateDisplay() {
    const readingsHTML = this.readings.map((reading) =>
      `<span class="inline-block px-2 py-1 bg-blue-100 text-blue-800 rounded text-sm mr-2 mb-2">
        ${reading} µm
      </span>`
    ).join("")

    this.readingsListTarget.innerHTML = readingsHTML ||
      '<span class="text-gray-400 text-sm">No readings yet...</span>'

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
      this.statisticsTarget.innerHTML = ""
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
    if (this.hasReadingsDataTarget) {
      this.readingsDataTarget.value = JSON.stringify(this.readings)
    }
  }

  clearReadings() {
    if (confirm("Clear all readings for this batch?")) {
      this.readings = []
      this.updateDisplay()
      this.updateHiddenField()
      if (this.session) this.session.refresh()
    }
  }

  loadExistingReadings() {
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

  flash() {
    if (this.hasStatisticsTarget) {
      this.statisticsTarget.classList.add("ring-2", "ring-blue-400")
      setTimeout(() => {
        this.statisticsTarget.classList.remove("ring-2", "ring-blue-400")
      }, 300)
    }
  }
}
