import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["table", "cards", "toggleButton"]

  connect() {
    this.checkViewport()
    this.boundCheckViewport = this.checkViewport.bind(this)
    window.addEventListener('resize', this.boundCheckViewport)
  }

  disconnect() {
    if (this.boundCheckViewport) {
      window.removeEventListener('resize', this.boundCheckViewport)
    }
  }

  checkViewport() {
    const isMobile = window.innerWidth < 1024

    if (this.hasTableTarget && this.hasCardsTarget) {
      if (isMobile) {
        this.tableTarget.classList.add('hidden')
        this.cardsTarget.classList.remove('hidden')
        if (this.hasToggleButtonTarget) {
          this.toggleButtonTarget.textContent = 'Table View'
        }
      } else {
        this.tableTarget.classList.remove('hidden')
        this.cardsTarget.classList.add('hidden')
        if (this.hasToggleButtonTarget) {
          this.toggleButtonTarget.textContent = 'Card View'
        }
      }
    }
  }

  toggleView() {
    if (this.hasTableTarget && this.hasCardsTarget) {
      const tableHidden = this.tableTarget.classList.contains('hidden')

      if (tableHidden) {
        this.tableTarget.classList.remove('hidden')
        this.cardsTarget.classList.add('hidden')
        this.toggleButtonTarget.textContent = 'Card View'
      } else {
        this.tableTarget.classList.add('hidden')
        this.cardsTarget.classList.remove('hidden')
        this.toggleButtonTarget.textContent = 'Table View'
      }
    }
  }
}
