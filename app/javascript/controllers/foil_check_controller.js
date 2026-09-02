// app/javascript/controllers/foil_check_controller.js
//
// Makes the foil verification CHECK inputs (measured_thickness_1/2 - the
// meter read against the calibrated foils) a sink on the shared
// elcometer-session, so the same connection fills them before the film
// readings. Attached to the foil strip of the foil op ONLY (never an
// ancestor of the film card, or its focusin would steal the card's
// preferred-target clicks).
//
// Document order puts this sink before the film card in the same op, so
// auto-routing does the physical sequence: foil check x2, then the film set.
// meter_no / foil_value_1/2 are typed (datalist) fields and are not touched -
// but they GATE the sink: until all three are recorded, acceptsReadings() is
// false and the session will not route meter readings into the check slots.
// That enforces the physical order (type calibration data, connect when
// happy, then measure) regardless of what the operator clicks first. The
// strip's own input listener refreshes the session, so the sink lights up
// the moment foil_value_2 is typed.

import { Controller } from "@hotwired/stimulus"

const FIELDS = ["measured_thickness_1", "measured_thickness_2"]
const TYPED_FIELDS = ["meter_no", "foil_value_1", "foil_value_2"]

// Advisory deviation limit for measured-vs-foil: matches the 5% window the
// calibration procedure works to (and MEASURED_WINDOW in FoilVerification).
const DEVIATION_LIMIT = 0.05

export default class extends Controller {
  static targets = ["warning"]

  connect() {
    this.session = null
    this.registerWithSession()
    this._onFocus = () => this.session && this.session.setPreferred(this)
    this._onInput = () => {
      if (this.session) this.session.refresh()
      this.checkDeviation()
    }
    this.element.addEventListener("focusin", this._onFocus)
    this.element.addEventListener("input", this._onInput)
    this.checkDeviation() // saved rows re-render with their values in place
  }

  disconnect() {
    this.element.removeEventListener("focusin", this._onFocus)
    this.element.removeEventListener("input", this._onInput)
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

  // ── Sink interface ───────────────────────────────────────────────────────

  inputs() {
    return FIELDS
      .map((f) => this.element.querySelector(`input[name$="[${f}]"]:not([disabled])`))
      .filter(Boolean)
  }

  emptyInputs() { return this.inputs().filter((i) => !i.value) }

  // Calibration data (meter identity + both foil values) typed yet?
  typedComplete() {
    return TYPED_FIELDS.every((f) => {
      const el = this.element.querySelector(`input[name$="[${f}]"]`)
      return el && el.value.trim() !== ""
    })
  }

  isActive() { return this.element.offsetParent !== null && this.inputs().length > 0 }

  sinkLabel() { return "Foil verification check" }

  acceptsReadings() {
    return this.isActive() && this.typedComplete() && this.emptyInputs().length > 0
  }

  isComplete() { return this.isActive() && this.emptyInputs().length === 0 }

  progress() {
    if (!this.isActive()) return { done: 0, expected: 0 }
    const all = this.inputs()
    return { done: all.length - this.emptyInputs().length, expected: all.length }
  }

  nextSlotLabel() {
    const all = this.inputs()
    const done = all.length - this.emptyInputs().length
    return `foil check ${Math.min(done + 1, all.length)}/${all.length}`
  }

  acceptReading(value) {
    if (!this.acceptsReadings()) return false
    const input = this.emptyInputs()[0]
    if (!input) return false
    input.value = value
    input.classList.add("ring-2", "ring-blue-400")
    setTimeout(() => input.classList.remove("ring-2", "ring-blue-400"), 300)
    if (this.session) this.session.refresh()
    this.checkDeviation()
    return true
  }

  // ── Calibration deviation check ──────────────────────────────────────────
  //
  // Compares each measured foil check against its calibrated foil value and
  // flags any pair more than DEVIATION_LIMIT off: red field + a message
  // naming the pair and the percentage. Advisory only - nothing is blocked,
  // because an out-of-window reading is exactly the one that must be
  // recorded and investigated, per the foil library's doctrine.

  checkDeviation() {
    const problems = []
    ;[1, 2].forEach((i) => {
      const foil = this.element.querySelector(`input[name$="[foil_value_${i}]"]`)
      const measured = this.element.querySelector(`input[name$="[measured_thickness_${i}]"]`)
      if (!foil || !measured) return
      const f = parseFloat(foil.value)
      const m = parseFloat(measured.value)
      const comparable = f > 0 && measured.value.trim() !== "" && !isNaN(m)
      const deviation = comparable ? Math.abs(m - f) / f : 0
      const bad = comparable && deviation > DEVIATION_LIMIT
      measured.classList.toggle("border-red-500", bad)
      measured.classList.toggle("bg-red-50", bad)
      if (bad) problems.push(`Foil ${i}: ${m} µm is ${(deviation * 100).toFixed(1)}% off the ${f} µm foil`)
    })
    if (!this.hasWarningTarget) return
    if (problems.length) {
      this.warningTarget.textContent =
        `${problems.join(" · ")} — over the 5% calibration limit. Recalibrate and re-check before measuring the work.`
      this.warningTarget.classList.remove("hidden")
    } else {
      this.warningTarget.classList.add("hidden")
    }
  }
}
