// app/javascript/controllers/navbar_controller.js - REPLACE ENTIRE FILE
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mobileMenu", "toggleButton"]

  connect() {
    // Use passive event listener for better performance
    this.boundHandleOutsideClick = this.handleOutsideClick.bind(this)
    document.addEventListener('click', this.boundHandleOutsideClick, { passive: true })
  }

  disconnect() {
    if (this.boundHandleOutsideClick) {
      document.removeEventListener('click', this.boundHandleOutsideClick)
    }
  }

  toggleMenu(event) {
    // Prevent default and stop propagation immediately
    event.preventDefault()
    event.stopPropagation()

    // Use requestAnimationFrame for smooth animation
    requestAnimationFrame(() => {
      if (this.mobileMenuTarget.classList.contains('hidden')) {
        this.openMenu()
      } else {
        this.closeMenu()
      }
    })
  }

  openMenu() {
    this.mobileMenuTarget.classList.remove('hidden')
    this.toggleButtonTarget.innerHTML = `
      <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
      </svg>
    `
  }

  closeMenu() {
    this.mobileMenuTarget.classList.add('hidden')
    this.toggleButtonTarget.innerHTML = `
      <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" />
      </svg>
    `
  }

  handleOutsideClick(event) {
    // Only check if menu is open (performance optimization)
    if (this.mobileMenuTarget.classList.contains('hidden')) return

    if (!this.element.contains(event.target)) {
      this.closeMenu()
    }
  }
}
