// app/javascript/controllers/sub_user_controller.js
// Registered as "sub-user" (Stimulus dasherises sub_user_controller.js).
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "modal", "card", "pin", "dots", "submit"]
  // GlobalID of whoever this page was rendered as ("" when nobody).
  static values = { actor: String }

  connect() {
    this.boundOutside = this.handleOutsideClick.bind(this)
    document.addEventListener("click", this.boundOutside)
    this.watchOtherTabs()
  }

  disconnect() {
    document.removeEventListener("click", this.boundOutside)
    if (this.channel) this.channel.close()
  }

  // --- cross-tab sync ---------------------------------------------------
  //
  // The operator lives on the server session, which every tab shares. A tab
  // left open while a colleague PINs in on another one still shows the old
  // name in the corner. The server refuses any write from such a tab (the
  // as_actor check), but better that the tab never looks wrong in the first
  // place: every page announces who it was rendered as, and a page holding
  // someone else reloads. The reload always lands on the session's truth, so
  // this converges in one hop and can't ping-pong.

  watchOtherTabs() {
    if (!("BroadcastChannel" in window)) return

    this.channel = new BroadcastChannel("hams-sub-user")
    this.channel.onmessage = (event) => {
      if (event.data !== this.actorValue) this.reload()
    }
    // Announce on connect only. A page that has just come back from the
    // server IS the session's truth, so whoever disagrees with it is stale.
    // Announcing on visibilitychange would be wrong: a stale tab coming to
    // the front would make the colleague's correct tab reload mid-entry.
    this.channel.postMessage(this.actorValue)
  }

  reload() {
    if (this.reloading) return
    this.reloading = true
    if (window.Turbo) {
      window.Turbo.visit(window.location.href, { action: "replace" })
    } else {
      window.location.reload()
    }
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
