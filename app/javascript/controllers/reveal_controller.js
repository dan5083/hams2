// app/javascript/controllers/reveal_controller.js
// Checkbox flips every "off" target hidden and every "on" target visible.
// Used by the ENP board's "Split by pretreatment" toggle; both layouts are
// server-rendered, so this is pure show/hide with no fetches.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["on", "off"]

  toggle(event) {
    const grouped = event.target.checked
    this.onTargets.forEach(el => el.classList.toggle("hidden", !grouped))
    this.offTargets.forEach(el => el.classList.toggle("hidden", grouped))
  }
}
