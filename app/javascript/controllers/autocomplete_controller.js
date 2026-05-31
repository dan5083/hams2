// app/javascript/controllers/autocomplete_controller.js
//
// Generic debounced autocomplete with an async JSON source, used by both the
// customer search and the "copy from existing part" search on the part form
// (which were previously two near-identical hand-rolled functions).
//
// Behaviour:
//   - debounced query (minLength gate), aborting any in-flight request
//   - renders up to three configurable fields per row (label / sublabel /
//     subtext) so simple and rich result rows share one renderer
//   - on select: optionally writes a value into a hidden field and/or the input,
//     flashes the input green, and dispatches `autocomplete:select` with
//     `{ detail: { item, input } }` so consumers can react to richer flows
//
// Markup:
//   <div data-controller="autocomplete"
//        data-autocomplete-url-value="/customer_orders/search_customers"
//        data-autocomplete-label-field-value="name"
//        data-autocomplete-value-field-value="id"
//        data-autocomplete-display-field-value="name"
//        data-autocomplete-empty-message-value="No customers found.">
//     <input data-autocomplete-target="input" ...>
//     <input type="hidden" data-autocomplete-target="hidden" ...>
//     <div data-autocomplete-target="dropdown" ...></div>
//     <div data-autocomplete-target="loading" ...></div>
//   </div>
import { Controller } from "@hotwired/stimulus"

const DEBOUNCE_MS = 300

export default class extends Controller {
  static targets = ["input", "hidden", "dropdown", "loading"]

  static values = {
    url: String,
    queryParam: { type: String, default: "q" },
    minLength: { type: Number, default: 2 },
    labelField: String,
    sublabelField: String,
    subtextField: String,
    valueField: String,
    displayField: String,
    emptyMessage: { type: String, default: "No results found." }
  }

  connect() {
    this.items = []
    this.boundOutsideClick = this.closeOnOutsideClick.bind(this)
    document.addEventListener("click", this.boundOutsideClick)
    this.inputTarget.addEventListener("input", () => this.onInput())
  }

  disconnect() {
    document.removeEventListener("click", this.boundOutsideClick)
    this.abortInFlight()
    clearTimeout(this.debounceTimer)
  }

  // ---------------------------------------------------------------------------
  // Querying
  // ---------------------------------------------------------------------------

  onInput() {
    const query = this.inputTarget.value.trim()
    clearTimeout(this.debounceTimer)
    this.abortInFlight()

    if (query.length < this.minLengthValue) {
      this.hideDropdown()
      if (this.hasHiddenTarget) this.hiddenTarget.value = ""
      return
    }

    this.showLoading()
    this.debounceTimer = setTimeout(() => this.search(query), DEBOUNCE_MS)
  }

  async search(query) {
    this.controller = new AbortController()

    try {
      const url = `${this.urlValue}?${this.queryParamValue}=${encodeURIComponent(query)}`
      const response = await fetch(url, {
        method: "GET",
        headers: { Accept: "application/json", "X-Requested-With": "XMLHttpRequest" },
        signal: this.controller.signal
      })
      const data = await response.json()
      this.hideLoading()
      this.render(data)
    } catch (error) {
      this.hideLoading()
      if (error.name !== "AbortError") console.error("Autocomplete error:", error)
    }
  }

  abortInFlight() {
    if (this.controller) this.controller.abort()
  }

  // ---------------------------------------------------------------------------
  // Rendering & selection
  // ---------------------------------------------------------------------------

  render(items) {
    this.items = items || []

    if (this.items.length === 0) {
      this.dropdownTarget.innerHTML = `<div class="px-4 py-3 text-sm text-gray-500">${this.emptyMessageValue}</div>`
    } else {
      this.dropdownTarget.innerHTML = this.items.map((item, index) => this.rowHtml(item, index)).join("")
      this.dropdownTarget.querySelectorAll("[data-index]").forEach((row) => {
        row.addEventListener("click", () => this.select(this.items[parseInt(row.dataset.index)]))
      })
    }

    this.showDropdown()
  }

  rowHtml(item, index) {
    const label = item[this.labelFieldValue] ?? ""
    const sublabel = this.sublabelFieldValue ? item[this.sublabelFieldValue] : null
    const subtext = this.subtextFieldValue ? item[this.subtextFieldValue] : null
    const hasDetail = sublabel != null || subtext != null
    const labelClass = hasDetail ? "font-medium text-gray-900" : "text-gray-900"

    return `
      <div class="dropdown-item px-4 py-3 cursor-pointer hover:bg-blue-50 text-sm border-b border-gray-100 last:border-b-0" data-index="${index}">
        <div class="${labelClass}">${label}</div>
        ${sublabel ? `<div class="text-xs text-gray-500">${sublabel}</div>` : ""}
        ${subtext ? `<div class="text-xs text-gray-600 mt-1">${subtext || "No operations"}</div>` : ""}
      </div>
    `
  }

  select(item) {
    if (this.hasHiddenTarget && this.valueFieldValue) {
      this.hiddenTarget.value = item[this.valueFieldValue]
    }

    if (this.displayFieldValue) {
      this.inputTarget.value = item[this.displayFieldValue]
      this.flashSuccess()
    }

    this.hideDropdown()
    this.dispatch("select", { detail: { item, input: this.inputTarget } })
  }

  flashSuccess() {
    this.inputTarget.style.borderColor = "#10b981"
    setTimeout(() => {
      this.inputTarget.style.borderColor = ""
    }, 1000)
  }

  // ---------------------------------------------------------------------------
  // Dropdown / loading visibility
  // ---------------------------------------------------------------------------

  showDropdown() {
    this.dropdownTarget.classList.remove("hidden")
  }

  hideDropdown() {
    this.dropdownTarget.classList.add("hidden")
  }

  showLoading() {
    if (this.hasLoadingTarget) this.loadingTarget.classList.remove("hidden")
  }

  hideLoading() {
    if (this.hasLoadingTarget) this.loadingTarget.classList.add("hidden")
  }

  closeOnOutsideClick(event) {
    if (!this.inputTarget.contains(event.target) && !this.dropdownTarget.contains(event.target)) {
      this.hideDropdown()
    }
  }
}
