// app/javascript/controllers/navbar_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mobileMenu", "toggleButton"]

  connect() {
    // Close menu when clicking outside
    this.boundHandleOutsideClick = this.handleOutsideClick.bind(this)
    document.addEventListener('click', this.boundHandleOutsideClick)
  }

  disconnect() {
    document.removeEventListener('click', this.boundHandleOutsideClick)
  }

  toggleMenu() {
    const menu = this.mobileMenuTarget

    if (menu.classList.contains('hidden')) {
      this.openMenu()
    } else {
      this.closeMenu()
    }
  }

  openMenu() {
    this.mobileMenuTarget.classList.remove('hidden')

    // Update button icon to X
    this.toggleButtonTarget.innerHTML = `
      <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
      </svg>
    `
  }

  closeMenu() {
    this.mobileMenuTarget.classList.add('hidden')

    // Update button icon to hamburger
    this.toggleButtonTarget.innerHTML = `
      <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" />
      </svg>
    `
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target) && !this.mobileMenuTarget.classList.contains('hidden')) {
      this.closeMenu()
    }
  }
}
