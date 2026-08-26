// app/javascript/controllers/sub_user_controller.js
// Registered as "sub-user" (Stimulus dasherises sub_user_controller.js).
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "modal", "card", "pin", "dots", "submit"]

  connect() {
    this.boundOutside = this.handleOutsideClick.bind(this)
    document.addEventListener("click", this.boundOutside)
  }

  disconnect() {
    document.removeEventListener("click", this.boundOutside)
  }

  // --- dropdown ---------------------------------------------------------

  toggleMenu(event) {
    event.preventDefault()
    event.stopPropagation()
    this.menuTarget.classList.toggle("hidden")
  }

  closeMenu() {
    if (this.hasMenuTarget) this.menuTarget.classList.add("hidden")
  }

  handleOutsideClick(event) {
    if (!this.hasMenuTarget || this.menuTarget.classList.contains("hidden")) return
    if (!this.element.contains(event.target)) this.closeMenu()
  }

  // --- PIN pad ----------------------------------------------------------

  // No operator to choose any more - the PIN identifies whoever types it.
  open(event) {
    if (event) event.preventDefault()
    this.closeMenu()
    this.pinTarget.value = ""
    this.render()
    this.modalTarget.classList.remove("hidden")
  }

  close(event) {
    if (event) event.preventDefault()
    this.pinTarget.value = ""
    this.render()
    this.modalTarget.classList.add("hidden")
  }

  backdrop(event) {
    // Only dismiss on the overlay itself, never on a click inside the card.
    if (event.target === this.modalTarget) this.close(event)
  }

  digit(event) {
    event.preventDefault()
    if (this.pinTarget.value.length >= 4) return

    this.pinTarget.value += String(event.params.digit)
    this.render()

    if (this.pinTarget.value.length === 4) {
      // Four digits is the whole input - no reason to make someone find a
      // confirm button with gloves on.
      setTimeout(() => this.pinTarget.form.requestSubmit(), 120)
    }
  }

  backspace(event) {
    event.preventDefault()
    this.pinTarget.value = this.pinTarget.value.slice(0, -1)
    this.render()
  }

  key(event) {
    if (this.modalTarget.classList.contains("hidden")) return

    if (event.key === "Escape") return this.close(event)
    if (event.key === "Backspace") return this.backspace(event)
    if (/^[0-9]$/.test(event.key)) {
      event.preventDefault()
      if (this.pinTarget.value.length >= 4) return
      this.pinTarget.value += event.key
      this.render()
      if (this.pinTarget.value.length === 4) {
        setTimeout(() => this.pinTarget.form.requestSubmit(), 120)
      }
    }
  }

  render() {
    const filled = this.pinTarget.value.length
    Array.from(this.dotsTarget.children).forEach((dot, index) => {
      const on = index < filled
      dot.classList.toggle("bg-[#e8028c]", on)
      dot.classList.toggle("border-[#e8028c]", on)
      dot.classList.toggle("border-gray-300", !on)
    })
  }
}
