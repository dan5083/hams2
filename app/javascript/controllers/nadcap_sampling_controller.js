// app/javascript/controllers/nadcap_sampling_controller.js
//
// Per-batch NADCAP sample-plan thickness measurements for MIL-PRF-8625F Type III.
// One controller instance per batch container. Renders a dynamic grid of sampled
// parts (B1p1, B1p2, ...). Sample size derived from parts-per-batch via the
// NADCAP plan table.
//
// Reading plan: the TOTAL readings for the batch is max(8, sample_size),
// distributed as evenly as possible across the sampled parts:
//   - Lot 1  → sample 1  → 8 readings on the one part          (8 total)
//   - Lot 6  → sample 6  → 2 parts × 2 readings, 4 parts × 1   (8 total)
//   - Lot 32 → sample 12 → 1 reading per part                  (12 total)
//   - Lot 300 → sample 16 → 1 reading per part                 (16 total)
// i.e. once the sample size reaches 8, every sampled part takes one reading.
//
// This controller NO LONGER owns the serial port. It registers as a "sink" with
// the shared elcometer-session controller, which owns the single Elcometer
// connection and routes readings here via acceptReading(). Manual entry, parts
// grid, stats and persistence remain local.
//
// Hidden field payload (per batch):
//   {
//     "parts_per_batch": 300,
//     "parts": [
//       { "part_label": "B1p1", "readings": [70.5, 70.8, ...] },  // per-part count from reading plan
//       ...
//     ]
//   }

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "partsPerBatchInput",
    "sampleSizeDisplay",
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

  // NADCAP sample plan: parts_per_batch -> sample size (parts to test).
  sampleSizeFor(n) {
    if (n < 1) return 0
    if (n <= 12)   return n     // All parts tested
    if (n <= 288)  return 12
    if (n <= 544)  return 16
    if (n <= 960)  return 20
    if (n <= 1632) return 24
    return 32
  }

  // Total readings required for the batch: max(8, sample_size).
  totalReadingsFor(n) {
    const ss = this.sampleSizeFor(n)
    return ss < 1 ? 0 : Math.max(8, ss)
  }

  // Reading plan: array of readings-per-part, length = sample size.
  // The total is distributed as evenly as possible; the first (total % ss)
  // parts take one extra reading. e.g. lot 6 → [2,2,1,1,1,1]; lot 32 → [1×12].
  readingsPlanFor(n) {
    const ss = this.sampleSizeFor(n)
    if (ss < 1) return []
    const total = Math.max(8, ss)
    const base  = Math.floor(total / ss)
    const extra = total % ss
    return Array.from({ length: ss }, (_, i) => base + (i < extra ? 1 : 0))
  }

  connect() {
    this.parts = []           // [{ label, readings: [r1..r8] }, ...]
    this.partsPerBatch = 0
    this.session = null

    this.loadExisting()
    this.registerWithSession()

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

  isActive() { return this.element.offsetParent !== null }

  sinkLabel() {
    return `${this.displayNameValue || "Hard Anodising"} · ${this.batchLabelValue}`
  }

  acceptsReadings() {
    if (!this.isActive() || this.partsPerBatch < 1 || this.parts.length === 0) return false
    return this.parts.some((p) => p.readings.some((r) => r == null))
  }

  isComplete() {
    return this.partsPerBatch >= 1 &&
           this.parts.length > 0 &&
           !this.parts.some((p) => p.readings.some((r) => r == null))
  }

  progress() {
    if (!this.isActive()) return { done: 0, expected: 0 }
    const expected = this.totalReadingsFor(this.partsPerBatch)
    const done = this.parts.reduce(
      (a, p) => a + p.readings.filter((r) => r != null && r !== "" && !isNaN(r)).length, 0
    )
    return { done, expected }
  }

  nextSlotLabel() {
    // Breadth-first: complete reading-round ri across all parts before
    // advancing to ri+1, matching the operator's whack-a-mole sweep.
    const maxSlots = Math.max(0, ...this.parts.map((p) => p.readings.length))
    for (let ri = 0; ri < maxSlots; ri++) {
      for (let pi = 0; pi < this.parts.length; pi++) {
        const r = this.parts[pi].readings
        if (ri < r.length && r[ri] == null) {
          const filled = r.filter((x) => x != null).length
          return `${this.parts[pi].label} · ${filled}/${r.length}`
        }
      }
    }
    return ""
  }

  // Fill the first empty slot BREADTH-FIRST (Hund's rule): one reading on each
  // part in a round, then loop back for the next round. Reading-round ri is the
  // outer loop, parts the inner, so ri=0 fills every part's slot 0 before any
  // part gets slot 1. Not every part has every slot (see reading plan), hence
  // the `ri < readings.length` guard. Returns true if placed.
  acceptReading(value) {
    const rounded = Math.round(value * 10) / 10
    const maxSlots = Math.max(0, ...this.parts.map((p) => p.readings.length))
    for (let ri = 0; ri < maxSlots; ri++) {
      for (let pi = 0; pi < this.parts.length; pi++) {
        if (ri < this.parts[pi].readings.length && this.parts[pi].readings[ri] == null) {
          this.parts[pi].readings[ri] = rounded

          const inp = this.hasPartsContainerTarget && this.partsContainerTarget.querySelector(
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
          if (this.session) this.session.refresh()
          return true
        }
      }
    }
    return false
  }

  // ── Parts-per-batch input handler ─────────────────────────────────────────

  updateSampleSize() {
    const raw = this.partsPerBatchInputTarget.value
    const n = parseInt(raw, 10)

    if (isNaN(n) || n < 1) {
      this.partsPerBatch = 0
      this.parts = []
      this.sampleSizeDisplayTarget.textContent = "Enter parts in this batch"
      this.partsContainerTarget.innerHTML = ""
      this.persist()
      this.renderBatchStats()
      if (this.session) this.session.refresh()
      return
    }

    const newPlan       = this.readingsPlanFor(n)
    const newSampleSize = newPlan.length
    const oldSampleSize = this.parts.length

    if (this.wouldDiscardReadings(newPlan)) {
      const ok = confirm(
        `Changing the lot size to ${n} resizes the sample plan ` +
        `(${oldSampleSize} → ${newSampleSize} sampled part(s)) and will discard ` +
        `some existing readings. Continue?`
      )
      if (!ok) {
        this.partsPerBatchInputTarget.value = this.partsPerBatch || ""
        return
      }
    }

    this.partsPerBatch = n
    this.resizeParts(newPlan)
    this.renderGrid()
    this.renderBatchStats()
    this.persist()
    this.updateSampleSizeDisplay()
    if (this.session) this.session.refresh()
  }

  updateSampleSizeDisplay() {
    const plan = this.readingsPlanFor(this.partsPerBatch)
    if (plan.length === 0) {
      this.sampleSizeDisplayTarget.textContent = "Enter parts in this batch"
      return
    }
    const total = plan.reduce((a, b) => a + b, 0)
    const max   = plan[0]
    const min   = plan[plan.length - 1]

    let breakdown
    if (max === min) {
      breakdown = `${plan.length} part(s) × ${max} reading(s)`
    } else {
      const extras = plan.filter((c) => c === max).length
      breakdown = `${extras} part(s) × ${max} readings + ${plan.length - extras} part(s) × ${min} reading`
    }
    this.sampleSizeDisplayTarget.textContent =
      `Sample size: ${plan.length} part(s) — ${breakdown} = ${total} readings`
  }

  // True if applying newPlan (array of per-part reading counts) would drop
  // any entered reading: either whole parts beyond the new sample size, or
  // trailing reading slots on parts whose allocation shrinks.
  wouldDiscardReadings(newPlan) {
    for (let pi = 0; pi < this.parts.length; pi++) {
      const keep = pi < newPlan.length ? newPlan[pi] : 0
      const r    = this.parts[pi].readings
      for (let ri = keep; ri < r.length; ri++) {
        if (r[ri] != null && r[ri] !== "") return true
      }
    }
    return false
  }

  // Resizes the parts array AND each part's readings array to match the plan.
  resizeParts(plan) {
    if (this.parts.length > plan.length) {
      this.parts = this.parts.slice(0, plan.length)
    }
    while (this.parts.length < plan.length) {
      const idx = this.parts.length
      this.parts.push({
        label:    `${this.batchLabelValue}p${idx + 1}`,
        readings: []
      })
    }
    this.parts.forEach((part, i) => {
      const target = plan[i]
      const r = part.readings.slice(0, target)
      while (r.length < target) r.push(null)
      part.readings = r
    })
  }

  // ── Grid rendering ──────────────────────────────────────────────────────

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
      `).join("")

      // Literal class strings (not interpolated) so Tailwind's content
      // scanner keeps them in the build.
      const gridCols = {
        1: "grid-cols-1", 2: "grid-cols-2", 3: "grid-cols-3", 4: "grid-cols-4",
        5: "grid-cols-5", 6: "grid-cols-6", 7: "grid-cols-7", 8: "grid-cols-8"
      }[Math.min(Math.max(part.readings.length, 1), 8)]

      return `
        <div class="border-l-2 border-blue-200 pl-3 py-2 bg-white rounded">
          <div class="flex items-center justify-between mb-1">
            <span class="text-xs font-semibold text-gray-700">${part.label}</span>
            <span class="text-xs text-gray-500" data-part-stats="${partIdx}"></span>
          </div>
          <div class="grid ${gridCols} gap-1">${inputs}</div>
        </div>
      `
    }).join("")

    this.partsContainerTarget.innerHTML = html
    this.parts.forEach((_, idx) => this.renderPartStats(idx))
  }

  // Per-part stats line; called on its own to avoid full grid re-render
  // (which would lose input focus).
  renderPartStats(partIdx) {
    const el = this.partsContainerTarget.querySelector(`[data-part-stats="${partIdx}"]`)
    if (!el) return

    const vals = this.parts[partIdx].readings.filter((r) => r != null && r !== "" && !isNaN(r))
    if (vals.length === 0) {
      el.textContent = ""
      return
    }
    const slots = this.parts[partIdx].readings.length
    const mean = (vals.reduce((a, b) => a + b, 0) / vals.length).toFixed(1)
    const min = Math.min(...vals)
    const max = Math.max(...vals)
    el.textContent = `${vals.length}/${slots} · mean ${mean} · min ${min} · max ${max}`
  }

  // ── Manual reading entry (blur on individual cell) ────────────────────────

  updateReading(event) {
    const input = event.target
    const partIdx = parseInt(input.dataset.partIndex, 10)
    const readingIdx = parseInt(input.dataset.readingIndex, 10)
    const valueStr = input.value.trim()

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
    if (this.session) this.session.refresh()
  }

  // ── Clear / persist / load ────────────────────────────────────────────────

  clearReadings() {
    if (!confirm(`Clear all readings for ${this.batchLabelValue}?`)) return
    this.parts.forEach((p) => (p.readings = Array(p.readings.length).fill(null)))
    this.renderGrid()
    this.renderBatchStats()
    this.persist()
    if (this.session) this.session.refresh()
    this.showSuccess(`${this.batchLabelValue} readings cleared`)
  }

  renderBatchStats() {
    if (!this.hasStatisticsTarget) return

    const allReadings = this.parts.flatMap((p) =>
      p.readings.filter((r) => r != null && r !== "" && !isNaN(r))
    )
    const expected = this.totalReadingsFor(this.partsPerBatch)

    if (allReadings.length === 0) {
      this.statisticsTarget.innerHTML = expected > 0
        ? `<div class="text-xs text-gray-500 mb-1">${this.batchLabelValue}: 0 / ${expected} readings</div>`
        : ""
      return
    }

    const sum = allReadings.reduce((a, b) => a + b, 0)
    const mean = Math.round((sum / allReadings.length) * 10) / 10
    const min = Math.min(...allReadings)
    const max = Math.max(...allReadings)

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
      parts: this.parts.map((p) => ({
        part_label: p.label,
        readings:   p.readings.filter((r) => r != null && r !== "" && !isNaN(r))
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

        const plan = this.readingsPlanFor(this.partsPerBatch)
        this.resizeParts(plan)

        if (Array.isArray(parsed.parts)) {
          parsed.parts.forEach((p, idx) => {
            if (idx >= this.parts.length) return
            const slots = plan[idx]
            const r = Array.isArray(p.readings) ? p.readings.slice(0, slots) : []
            this.parts[idx].readings = [...r, ...Array(Math.max(0, slots - r.length)).fill(null)]
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

  // ── Notifications ─────────────────────────────────────────────────────────

  showSuccess(msg) { this.showNotification(msg, "success") }
  showError(msg)   { this.showNotification(msg, "error") }
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
