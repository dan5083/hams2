// app/javascript/controllers/nadcap_sampling_controller.js
//
// Per-batch NADCAP sample-plan thickness measurements for MIL-PRF-8625F Type III.
// One controller instance per batch container. Renders a dynamic grid of
// sampled parts (B1p1, B1p2, ...), each with 8 reading inputs. Sample size
// derived from parts-per-batch via the NADCAP plan table.
//
// Hidden field payload (per batch):
//   {
//     "parts_per_batch": 300,
//     "parts": [
//       { "part_label": "B1p1", "readings": [70.5, 70.8, ...] },  // 8 readings
//       ...
//     ]
//   }

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "partsPerBatchInput",
    "sampleSizeDisplay",
    "connectButton",
    "stopButton",
    "partsContainer",
    "statistics",
    "readingsData"
  ]

  static values = {
    treatmentId:     String,    // batch_tid, e.g. "abc123_b1"
    batchNumber:     Number,
    batchLabel:      String,    // "B1", "B2", ...
    processType:     String,
    targetThickness: Number,
    displayName:     String
  }

  // ---------------------------------------------------------------------------
  // NADCAP sample plan: parts_per_batch -> sample size (parts to test)
  // 8 readings required per sampled part.
  // ---------------------------------------------------------------------------
  sampleSizeFor(n) {
    if (n < 1) return 0
    if (n <= 12)   return n     // All parts tested
    if (n <= 288)  return 12
    if (n <= 544)  return 16
    if (n <= 960)  return 20
    if (n <= 1632) return 24
    return 32
  }

  connect() {
    this.parts          = []    // [{ label, readings: [r1..r8] }, ...]
    this.partsPerBatch  = 0
    this.port           = null
    this.reader         = null
    this.isReading      = false

    if (!("serial" in navigator)) {
      this.showError("Web Serial API not supported. Use Chrome or Edge.")
      if (this.hasConnectButtonTarget) this.connectButtonTarget.disabled = true
    }

    this.loadExisting()
  }

  disconnect() {
    this.stopReading()
  }

  // ---------------------------------------------------------------------------
  // Parts-per-batch input handler
  // ---------------------------------------------------------------------------
  updateSampleSize() {
    const raw = this.partsPerBatchInputTarget.value
    const n   = parseInt(raw, 10)

    if (isNaN(n) || n < 1) {
      this.partsPerBatch = 0
      this.parts = []
      this.sampleSizeDisplayTarget.textContent = "Enter parts in this batch"
      this.partsContainerTarget.innerHTML = ""
      this.persist()
      this.renderBatchStats()
      return
    }

    const newSampleSize = this.sampleSizeFor(n)
    const oldSampleSize = this.parts.length

    if (newSampleSize < oldSampleSize && this.hasAnyReadings(newSampleSize)) {
      const ok = confirm(
        `Reducing sample size from ${oldSampleSize} to ${newSampleSize} part(s) ` +
        `will discard readings from ${oldSampleSize - newSampleSize} sampled part(s). Continue?`
      )
      if (!ok) {
        this.partsPerBatchInputTarget.value = this.partsPerBatch || ""
        return
      }
    }

    this.partsPerBatch = n
    this.resizeParts(newSampleSize)
    this.renderGrid()
    this.renderBatchStats()
    this.persist()
    this.updateSampleSizeDisplay()
  }

  updateSampleSizeDisplay() {
    const ss = this.sampleSizeFor(this.partsPerBatch)
    if (ss <= 0) {
      this.sampleSizeDisplayTarget.textContent = "Enter parts in this batch"
      return
    }
    this.sampleSizeDisplayTarget.textContent =
      `Sample size: ${ss} part(s) × 8 readings = ${ss * 8} readings`
  }

  hasAnyReadings(beyondIndex = 0) {
    // True if any reading exists at part index >= beyondIndex
    for (let pi = beyondIndex; pi < this.parts.length; pi++) {
      if (this.parts[pi].readings.some(r => r != null && r !== "")) return true
    }
    return false
  }

  resizeParts(newCount) {
    while (this.parts.length < newCount) {
      const idx = this.parts.length
      this.parts.push({
        label:    `${this.batchLabelValue}p${idx + 1}`,
        readings: Array(8).fill(null)
      })
    }
    if (this.parts.length > newCount) {
      this.parts = this.parts.slice(0, newCount)
    }
  }

  // ---------------------------------------------------------------------------
  // Grid rendering
  // ---------------------------------------------------------------------------
  renderGrid() {
    if (!this.hasPartsContainerTarget) return

    const html = this.parts.map((part, partIdx) => {
      const inputs = part.readings.map((r, rIdx) => `
        <input type="number"
               step="0.1" min="0"
               data-part-index="${partIdx}"
               data-reading-index="${rIdx}"
               data-action="blur->nadcap-sampling#updateReading"
               value="${r ?? ''}"
               class="block w-full text-sm border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500"
               placeholder="${rIdx + 1}" />
      `).join('')

      return `
        <div class="border-l-2 border-blue-200 pl-3 py-2 bg-white rounded">
          <div class="flex items-center justify-between mb-1">
            <span class="text-xs font-semibold text-gray-700">${part.label}</span>
            <span class="text-xs text-gray-500" data-part-stats="${partIdx}"></span>
          </div>
          <div class="grid grid-cols-8 gap-1">${inputs}</div>
        </div>
      `
    }).join('')

    this.partsContainerTarget.innerHTML = html
    this.parts.forEach((_, idx) => this.renderPartStats(idx))
  }

  // Per-part stats line; called on its own to avoid full grid re-render
  // (which would lose input focus)
  renderPartStats(partIdx) {
    const el = this.partsContainerTarget.querySelector(`[data-part-stats="${partIdx}"]`)
    if (!el) return

    const vals = this.parts[partIdx].readings.filter(r =>
      r != null && r !== "" && !isNaN(r)
    )
    if (vals.length === 0) {
      el.textContent = ""
      return
    }
    const mean = (vals.reduce((a, b) => a + b, 0) / vals.length).toFixed(1)
    const min  = Math.min(...vals)
    const max  = Math.max(...vals)
    el.textContent = `${vals.length}/8 · mean ${mean} · min ${min} · max ${max}`
  }

  // ---------------------------------------------------------------------------
  // Manual reading entry (blur on individual cell)
  // ---------------------------------------------------------------------------
  updateReading(event) {
    const input      = event.target
    const partIdx    = parseInt(input.dataset.partIndex, 10)
    const readingIdx = parseInt(input.dataset.readingIndex, 10)
    const valueStr   = input.value.trim()

    if (!valueStr) {
      this.parts[partIdx].readings[readingIdx] = null
    } else {
      const v = parseFloat(valueStr)
      if (isNaN(v) || v <= 0) {
        this.showError(`Invalid value for ${this.parts[partIdx].label} reading ${readingIdx + 1}`)
        input.value = ""
        this.parts[partIdx].readings[readingIdx] = null
      } else {
        const rounded = Math.round(v * 10) / 10
        this.parts[partIdx].readings[readingIdx] = rounded
        input.value = rounded
      }
    }

    this.renderPartStats(partIdx)
    this.renderBatchStats()
    this.persist()
  }

  // ---------------------------------------------------------------------------
  // Elcometer Web Serial (mirrors elcometer_controller pattern)
  // ---------------------------------------------------------------------------
  async connectElcometer() {
    if (this.parts.length === 0) {
      this.showError("Set 'Parts in this batch' before connecting the Elcometer")
      return
    }

    try {
      this.port = await navigator.serial.requestPort()
      await this.port.open({ baudRate: 9600, dataBits: 8, stopBits: 1, parity: "none" })

      this.showSuccess(`✅ Connected to Elcometer for ${this.batchLabelValue}`)
      this.connectButtonTarget.classList.add("hidden")
      this.stopButtonTarget.classList.remove("hidden")

      this.isReading = true
      this.startReading()
    } catch (err) {
      if (err.name === "NotFoundError") {
        this.showError("No device selected")
      } else {
        this.showError(`Connection error: ${err.message}`)
      }
      console.error("NADCAP Elcometer connection error:", err)
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
        buffer += value
        const lines = buffer.split("\n")
        buffer = lines.pop()
        for (const line of lines) {
          this.processSerialReading(line)
        }
      }
    } catch (err) {
      if (this.isReading) {
        this.showError(`Reading error: ${err.message}`)
        console.error("NADCAP reading error:", err)
      }
    }
  }

  processSerialReading(line) {
    const match = line.match(/\s*([\d.]+)\s*um/i)
    if (!match) return

    const value = parseFloat(match[1])
    if (isNaN(value) || value <= 0) return

    // Fill the first empty slot, scanning p1[0..7] -> p2[0..7] -> ...
    for (let pi = 0; pi < this.parts.length; pi++) {
      for (let ri = 0; ri < 8; ri++) {
        if (this.parts[pi].readings[ri] == null) {
          const rounded = Math.round(value * 10) / 10
          this.parts[pi].readings[ri] = rounded

          const inp = this.partsContainerTarget.querySelector(
            `input[data-part-index="${pi}"][data-reading-index="${ri}"]`
          )
          if (inp) {
            inp.value = rounded
            inp.classList.add("ring-2", "ring-blue-400")
            setTimeout(() => inp.classList.remove("ring-2", "ring-blue-400"), 300)
          }
          this.renderPartStats(pi)
          this.renderBatchStats()
          this.persist()
          return
        }
      }
    }
    this.showWarning(`${this.batchLabelValue} all slots full - reading ignored`)
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
      if (this.hasConnectButtonTarget) this.connectButtonTarget.classList.remove("hidden")
      if (this.hasStopButtonTarget)    this.stopButtonTarget.classList.add("hidden")
    } catch (err) {
      console.error("NADCAP stop error:", err)
    }
  }

  // ---------------------------------------------------------------------------
  // Clear / persist / load
  // ---------------------------------------------------------------------------
  clearReadings() {
    if (!confirm(`Clear all readings for ${this.batchLabelValue}?`)) return
    this.parts.forEach(p => p.readings = Array(8).fill(null))
    this.renderGrid()
    this.renderBatchStats()
    this.persist()
    this.showSuccess(`${this.batchLabelValue} readings cleared`)
  }

  renderBatchStats() {
    if (!this.hasStatisticsTarget) return

    const allReadings = this.parts.flatMap(p =>
      p.readings.filter(r => r != null && r !== "" && !isNaN(r))
    )
    const expected = this.sampleSizeFor(this.partsPerBatch) * 8

    if (allReadings.length === 0) {
      this.statisticsTarget.innerHTML = expected > 0
        ? `<div class="text-xs text-gray-500 mb-1">${this.batchLabelValue}: 0 / ${expected} readings</div>`
        : ""
      return
    }

    const sum  = allReadings.reduce((a, b) => a + b, 0)
    const mean = Math.round((sum / allReadings.length) * 10) / 10
    const min  = Math.min(...allReadings)
    const max  = Math.max(...allReadings)

    this.statisticsTarget.innerHTML = `
      <div class="grid grid-cols-4 gap-4 p-3 bg-gray-50 rounded-md">
        <div>
          <div class="text-xs text-gray-500">${this.batchLabelValue} Progress</div>
          <div class="text-lg font-semibold text-gray-900">${allReadings.length}/${expected}</div>
        </div>
        <div>
          <div class="text-xs text-gray-500">Mean</div>
          <div class="text-lg font-semibold text-blue-600">${mean} µm</div>
        </div>
        <div>
          <div class="text-xs text-gray-500">Min</div>
          <div class="text-lg font-semibold text-gray-900">${min} µm</div>
        </div>
        <div>
          <div class="text-xs text-gray-500">Max</div>
          <div class="text-lg font-semibold text-gray-900">${max} µm</div>
        </div>
      </div>
    `
  }

  persist() {
    if (!this.hasReadingsDataTarget) return

    if (this.partsPerBatch < 1 || this.parts.length === 0) {
      this.readingsDataTarget.value = ""
      return
    }

    const payload = {
      parts_per_batch: this.partsPerBatch,
      parts: this.parts.map(p => ({
        part_label: p.label,
        readings:   p.readings.filter(r => r != null && r !== "" && !isNaN(r))
      }))
    }
    this.readingsDataTarget.value = JSON.stringify(payload)
  }

  loadExisting() {
    if (!this.hasReadingsDataTarget) return
    const raw = this.readingsDataTarget.value
    if (!raw) {
      this.sampleSizeDisplayTarget.textContent = "Enter parts in this batch"
      return
    }

    try {
      const parsed = JSON.parse(raw)
      if (parsed && typeof parsed === "object" && parsed.parts_per_batch) {
        this.partsPerBatch = parseInt(parsed.parts_per_batch, 10)
        this.partsPerBatchInputTarget.value = this.partsPerBatch

        const sampleSize = this.sampleSizeFor(this.partsPerBatch)
        this.resizeParts(sampleSize)

        if (Array.isArray(parsed.parts)) {
          parsed.parts.forEach((p, idx) => {
            if (idx >= this.parts.length) return
            const r = Array.isArray(p.readings) ? p.readings.slice(0, 8) : []
            this.parts[idx].readings = [...r, ...Array(Math.max(0, 8 - r.length)).fill(null)]
            if (p.part_label) this.parts[idx].label = p.part_label
          })
        }

        this.renderGrid()
        this.renderBatchStats()
        this.updateSampleSizeDisplay()
      }
    } catch (err) {
      console.error("NADCAP load error:", err)
    }
  }

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------
  showSuccess(msg) { this.showNotification(msg, "success") }
  showError(msg)   { this.showNotification(msg, "error")   }
  showWarning(msg) { this.showNotification(msg, "warning") }

  showNotification(message, type) {
    let container = document.getElementById("nadcap-notifications")
    if (!container) {
      container = document.createElement("div")
      container.id = "nadcap-notifications"
      container.className = "fixed top-4 right-4 z-50 space-y-2"
      document.body.appendChild(container)
    }

    const colors = {
      success: "bg-green-50 border-green-200 text-green-800",
      error:   "bg-red-50 border-red-200 text-red-800",
      warning: "bg-amber-50 border-amber-200 text-amber-800"
    }

    const n = document.createElement("div")
    n.className = `${colors[type]} border rounded-md p-3 shadow-lg max-w-sm`
    n.innerHTML = `
      <div class="flex items-start">
        <div class="flex-1 text-sm">${message}</div>
        <button class="ml-3 text-gray-400 hover:text-gray-600" onclick="this.parentElement.parentElement.remove()">
          <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"/>
          </svg>
        </button>
      </div>
    `
    container.appendChild(n)
    setTimeout(() => n.remove(), 4000)
  }
}
