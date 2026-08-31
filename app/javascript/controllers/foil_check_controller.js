// app/javascript/controllers/foil_check_controller.js
//
// Makes the foil verification CHECK inputs (measured_thickness_1/2 - the
// meter read against the calibrated foils) a sink on the shared
// elcometer-session, so the same connection fills them before the film
// readings. Attached to the plain-fields row of the foil op ONLY (never an
// ancestor of the film card, or its focusin would steal the card's
// preferred-target clicks).
//
// Document order puts this sink before the film card in the same op, so
// auto-routing does the physical sequence: foil check x2, then the film set.
// meter_no / foil_value_1/2 are typed (datalist) fields and are not touched.

import { Controller } from "@hotwired/stimulus"

const FIELDS = ["measured_thickness_1", "measured_thickness_2"]

export default class extends Controller {
  connect() {
    this.session = null
    this.registerWithSession()
    this._onFocus = () => this.session && this.session.setPreferred(this)
    this._onInput = () => this.session && this.session.refresh()
    this.element.addEventListener("focusin", this._onFocus)
    this.element.addEventListener("input", this._onInput)
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

  isActive() { return this.element.offsetParent !== null && this.inputs().length > 0 }

  sinkLabel() { return "Foil verification check" }

  acceptsReadings() { return this.isActive() && this.emptyInputs().length > 0 }

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
    const input = this.emptyInputs()[0]
    if (!input) return false
    input.value = value
    input.classList.add("ring-2", "ring-blue-400")
    setTimeout(() => input.classList.remove("ring-2", "ring-blue-400"), 300)
    if (this.session) this.session.refresh()
    return true
  }
}
