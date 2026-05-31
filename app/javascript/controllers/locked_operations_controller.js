// app/javascript/controllers/locked_operations_controller.js
//
// Manual operation management for parts whose operations are locked for
// editing. Handles the "add operation" modal, inserting / deleting / reordering
// operations against the server, and auto-saving operation text on blur.
//
// Attach to the operations section in the locked-editing view:
//   <div data-controller="locked-operations"> … #operations-container … </div>
//
// This was previously fused into parts_form_controller.js (guarded by an
// `isLockedMode` flag) together with the loose <script> auto-save helpers in
// the form partial. Behaviour is unchanged; it just lives in one place now.
import { Controller } from "@hotwired/stimulus"

const MODAL_ID = "insert-operation-modal"
const AUTOSAVE_DEBOUNCE_MS = 500
const DELETE_DEBOUNCE_MS = 1000

export default class extends Controller {
  connect() {
    this.partId = this.getPartIdFromUrl()
    if (!this.partId) {
      console.error("Part ID not found for manual operation management")
      return
    }

    this.currentInsertPosition = null
    this.deleteInProgress = false
    this.selectedOperation = null // set when a library operation is chosen

    this.setupModalEventListeners()

    // Delegate add/delete/reorder clicks within this section.
    this.boundClickHandler = this.handleClick.bind(this)
    this.element.addEventListener("click", this.boundClickHandler)

    this.setupOperationAutoSave()
  }

  disconnect() {
    if (this.boundClickHandler) {
      this.element.removeEventListener("click", this.boundClickHandler)
    }
    if (this.boundEscHandler) {
      document.removeEventListener("keydown", this.boundEscHandler)
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  get operationsContainer() {
    return this.element.querySelector("#operations-container")
  }

  getPartIdFromUrl() {
    const pathParts = window.location.pathname.split("/")
    const partsIndex = pathParts.indexOf("parts")
    return partsIndex !== -1 && pathParts[partsIndex + 1] ? pathParts[partsIndex + 1] : null
  }

  async request(url, method, body) {
    const response = await fetch(url, {
      method,
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken
      },
      body: JSON.stringify(body)
    })
    return response.json()
  }

  // ---------------------------------------------------------------------------
  // Click delegation
  // ---------------------------------------------------------------------------

  handleClick(event) {
    const target = event.target

    if (target.classList.contains("add-operation-btn")) {
      this.showInsertModal(parseInt(target.dataset.insertPosition))
    } else if (target.classList.contains("delete-operation-btn") && !this.deleteInProgress) {
      this.deleteOperation(parseInt(target.dataset.position))
    } else if (target.classList.contains("reorder-up-btn")) {
      const from = parseInt(target.dataset.position)
      this.reorderOperation(from, from - 1)
    } else if (target.classList.contains("reorder-down-btn")) {
      const from = parseInt(target.dataset.position)
      this.reorderOperation(from, from + 1)
    } else {
      return
    }

    event.preventDefault()
    event.stopPropagation()
  }

  // ---------------------------------------------------------------------------
  // Modal (markup is rendered server-side in the partial)
  // ---------------------------------------------------------------------------

  setupModalEventListeners() {
    const modal = document.getElementById(MODAL_ID)
    if (!modal) return

    const closeModal = () => this.hideInsertModal()

    document.getElementById("modal-cancel-btn").addEventListener("click", closeModal)
    modal.querySelector(".modal-backdrop").addEventListener("click", closeModal)
    document.getElementById("modal-confirm-btn").addEventListener("click", () => this.confirmInsert())

    // Typing in the name field (real keystrokes, not a programmatic fill from a
    // suggestion) means the user is naming their own operation: drop back to
    // custom mode so we don't silently attach a stale library identity.
    document.getElementById("modal-operation-name").addEventListener("input", () => {
      this.clearLibrarySelection()
    })

    this.boundEscHandler = (e) => {
      if (e.key === "Escape" && !modal.classList.contains("hidden")) closeModal()
    }
    document.addEventListener("keydown", this.boundEscHandler)
  }

  // Fired by the modal's autocomplete (autocomplete:select) when the user picks
  // a known operation from the library. Prefill the instructions and remember
  // the operation so confirm inserts it with its real identity/metadata.
  useLibraryOperation(event) {
    const op = event.detail.item
    this.selectedOperation = op

    const textInput = document.getElementById("modal-operation-text")
    if (textInput) textInput.value = op.operation_text || ""

    this.setModeIndicator(`Using library operation: ${op.display_name}`, true)
  }

  clearLibrarySelection() {
    this.selectedOperation = null
    this.setModeIndicator("No match selected — a custom operation will be created.", false)
  }

  setModeIndicator(text, isLibrary) {
    const indicator = document.getElementById("modal-operation-mode")
    if (!indicator) return
    indicator.textContent = text
    indicator.className = `text-xs mb-4 ${isLibrary ? "text-green-700" : "text-gray-500"}`
  }

  showInsertModal(position) {
    this.currentInsertPosition = position

    const modal = document.getElementById(MODAL_ID)
    const nameInput = document.getElementById("modal-operation-name")
    const textInput = document.getElementById("modal-operation-text")

    document.getElementById("modal-subtitle").textContent = `Adding operation at position ${position}`
    nameInput.value = ""
    textInput.value = ""
    this.clearLibrarySelection()

    modal.classList.remove("hidden")
    setTimeout(() => nameInput.focus(), 100)
  }

  hideInsertModal() {
    document.getElementById(MODAL_ID).classList.add("hidden")
    this.currentInsertPosition = null
  }

  confirmInsert() {
    const operationName = document.getElementById("modal-operation-name").value.trim()
    const textInput = document.getElementById("modal-operation-text")
    const operationText = textInput.value.trim()

    if (!operationText) {
      alert("Please enter operation instructions")
      textInput.focus()
      return
    }

    // A library operation only "sticks" if one was selected and the name hasn't
    // since been edited (editing the name clears the selection → custom op).
    const library = this.selectedOperation
    const operationId = library ? library.id : null
    const meta = library
      ? {
          specifications: library.specifications,
          process_type: library.process_type,
          target_thickness: library.target_thickness
        }
      : null

    this.insertOperationAtPosition(
      this.currentInsertPosition,
      operationText,
      operationName || (library ? library.display_name : "Custom Operation"),
      operationId,
      meta
    )
    this.hideInsertModal()
  }

  // ---------------------------------------------------------------------------
  // Insert / delete / reorder
  // ---------------------------------------------------------------------------

  async insertOperationAtPosition(position, operationText, displayName, operationId = null, meta = null) {
    const tempId = `temp_${Date.now()}`
    const container = this.operationsContainer
    const existingOperations = Array.from(container.querySelectorAll(".operation-item"))

    // Find the first operation at/after the target position to insert before.
    const insertBeforeElement =
      existingOperations.find((op) => parseInt(op.dataset.position) >= position) || null

    const newOperationHTML = this.createOperationHTML(position, displayName, operationText, tempId, meta)

    if (insertBeforeElement) {
      // If an "Add Operation" button sits immediately before, insert before it.
      const previous = insertBeforeElement.previousElementSibling
      const anchor =
        previous && previous.querySelector(".add-operation-btn") ? previous : insertBeforeElement
      anchor.insertAdjacentHTML("beforebegin", newOperationHTML)
    } else {
      const lastAddButton = container.querySelector(
        ".add-operation-btn[data-insert-position]:last-of-type"
      )
      if (lastAddButton) {
        lastAddButton.closest("div").insertAdjacentHTML("beforebegin", newOperationHTML)
      } else {
        container.insertAdjacentHTML("beforeend", newOperationHTML)
      }
    }

    this.storeOriginalPositions()
    this.renumberOperations()
    this.regenerateAddButtons()

    try {
      const body = { position, operation_text: operationText, display_name: displayName }
      if (operationId) body.operation_id = operationId

      const data = await this.request(`/parts/${this.partId}/insert_operation`, "POST", body)

      if (data.success) {
        const tempOp = document.querySelector(`[data-temp-id="${tempId}"]`)
        if (tempOp) {
          tempOp.removeAttribute("data-temp-id")
          tempOp.classList.remove("bg-green-100")
          tempOp.classList.add("bg-gray-50")
        }
        this.showSuccessMessage("Operation added successfully")
        this.regenerateAddButtons()
      } else {
        this.revertInsert(tempId)
        alert("Error: " + data.error)
      }
    } catch (error) {
      console.error("Error:", error)
      this.revertInsert(tempId)
      alert("An error occurred while adding the operation")
    }
  }

  revertInsert(tempId) {
    document.querySelector(`[data-temp-id="${tempId}"]`)?.remove()
    this.revertOperationPositions()
  }

  async deleteOperation(position) {
    if (this.deleteInProgress) return
    this.deleteInProgress = true

    try {
      if (!confirm("Are you sure you want to delete this operation? This cannot be undone.")) {
        this.deleteInProgress = false
        return
      }

      const data = await this.request(`/parts/${this.partId}/delete_operation`, "DELETE", { position })

      if (data.success) {
        location.reload()
      } else {
        alert("Error: " + data.error)
      }
    } catch (error) {
      console.error("Error:", error)
      alert("An error occurred while deleting the operation")
    } finally {
      setTimeout(() => {
        this.deleteInProgress = false
      }, DELETE_DEBOUNCE_MS)
    }
  }

  async reorderOperation(fromPosition, toPosition) {
    try {
      const data = await this.request(`/parts/${this.partId}/reorder_operation`, "PATCH", {
        from_position: fromPosition,
        to_position: toPosition
      })

      if (data.success) {
        location.reload()
      } else {
        alert("Error: " + data.error)
      }
    } catch (error) {
      console.error("Error:", error)
      alert("An error occurred while reordering the operation")
    }
  }

  // ---------------------------------------------------------------------------
  // Position bookkeeping
  // ---------------------------------------------------------------------------

  // Apply a 1-based position to a single operation item: data attribute, header
  // text, textarea name (non-temp only), and reorder/delete button positions.
  applyPositionToItem(item, position) {
    item.dataset.position = position

    const header = item.querySelector("h4")
    if (header) {
      header.textContent = header.textContent.replace(/Operation \d+:/, `Operation ${position}:`)
    }

    if (!item.dataset.tempId) {
      const textarea = item.querySelector("textarea")
      if (textarea) textarea.name = `locked_operations[${position}]`
    }

    item
      .querySelectorAll(".reorder-up-btn, .reorder-down-btn")
      .forEach((btn) => (btn.dataset.position = position))

    const deleteBtn = item.querySelector(".delete-operation-btn")
    if (deleteBtn) deleteBtn.dataset.position = position
  }

  renumberOperations() {
    document
      .querySelectorAll(".operation-item")
      .forEach((item, index) => this.applyPositionToItem(item, index + 1))
  }

  regenerateAddButtons() {
    const container = this.operationsContainer

    // Remove all existing "Add Operation" button rows.
    container.querySelectorAll("div").forEach((div) => {
      if (div.querySelector(".add-operation-btn")) div.remove()
    })

    const operations = Array.from(container.querySelectorAll(".operation-item"))

    operations.forEach((operation, index) => {
      if (index > 0) {
        const position = parseInt(operation.dataset.position)
        operation.insertAdjacentHTML("beforebegin", this.addButtonHTML(position, "+ Add Operation Here"))
      }
    })

    const lastPosition =
      operations.length > 0 ? parseInt(operations[operations.length - 1].dataset.position) + 1 : 1
    container.insertAdjacentHTML("beforeend", this.addButtonHTML(lastPosition, "+ Add Operation at End"))
  }

  addButtonHTML(position, label) {
    return `
      <div class="flex justify-center py-2">
        <button type="button" class="add-operation-btn bg-blue-100 hover:bg-blue-200 text-blue-700 px-4 py-2 rounded-lg text-sm border border-blue-300 transition-colors"
                data-insert-position="${position}">
          ${label}
        </button>
      </div>
    `
  }

  createOperationHTML(position, displayName, operationText, tempId, meta = null) {
    const processType = meta?.process_type || "manual"
    const typeLabel = processType.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase())
    const thickness = meta?.target_thickness
    const specifications = meta?.specifications

    const specsHtml = specifications
      ? `<p class="mt-2 text-xs text-purple-600"><strong>Specifications:</strong> ${specifications}</p>`
      : ""
    const thicknessBadge =
      thickness && thickness > 0
        ? `<span class="bg-yellow-100 text-yellow-800 px-2 py-1 rounded">Target: ${thickness}μm</span>`
        : ""

    return `
      <div class="border border-gray-200 rounded-lg p-4 bg-green-100 operation-item transition-colors duration-1000" data-position="${position}" data-temp-id="${tempId}">
        <div class="flex justify-between items-start mb-3">
          <div class="flex items-center space-x-3">
            <h4 class="font-medium text-gray-900">Operation ${position}: ${displayName}</h4>
          </div>
          <div class="flex items-center space-x-2">
            <button type="button" class="reorder-up-btn text-blue-600 hover:text-blue-800 text-sm font-medium" data-position="${position}" title="Move up">↑</button>
            <button type="button" class="reorder-down-btn text-blue-600 hover:text-blue-800 text-sm font-medium" data-position="${position}" title="Move down">↓</button>
            <button type="button" class="delete-operation-btn text-red-600 hover:text-red-800 text-xl font-bold" data-position="${position}" title="Delete this operation">×</button>
          </div>
        </div>
        <textarea name="locked_operations[${position}]" rows="3" class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm">${operationText}</textarea>
        ${specsHtml}
        <div class="flex flex-wrap gap-2 mt-2 text-xs text-gray-500">
          <span class="bg-blue-100 text-blue-800 px-2 py-1 rounded">Type: ${typeLabel}</span>
          ${thicknessBadge}
        </div>
      </div>
    `
  }

  storeOriginalPositions() {
    this.originalPositions = []
    document.querySelectorAll(".operation-item").forEach((item) => {
      this.originalPositions.push({ element: item, position: parseInt(item.dataset.position) })
    })
  }

  revertOperationPositions() {
    if (!this.originalPositions) return
    this.originalPositions.forEach(({ element, position }) =>
      this.applyPositionToItem(element, position)
    )
  }

  showSuccessMessage(message) {
    const successDiv = document.createElement("div")
    successDiv.className =
      "fixed top-4 right-4 bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded z-50"
    successDiv.textContent = message
    document.body.appendChild(successDiv)
    setTimeout(() => successDiv.remove(), 3000)
  }

  // ---------------------------------------------------------------------------
  // Operation text auto-save (on blur)
  // ---------------------------------------------------------------------------

  setupOperationAutoSave() {
    this.element.querySelectorAll("textarea.operation-textarea").forEach((textarea) => {
      let saveTimeout

      textarea.addEventListener("blur", () => {
        const match = textarea.name.match(/\[(\d+)\]/)
        if (!match) return

        const position = parseInt(match[1])
        const newText = textarea.value.trim()

        clearTimeout(saveTimeout)
        saveTimeout = setTimeout(() => this.saveOperationText(position, newText, textarea), AUTOSAVE_DEBOUNCE_MS)
      })
    })
  }

  async saveOperationText(position, text, textarea) {
    if (!this.partId) return

    textarea.style.backgroundColor = "#fef3c7" // saving (light yellow)

    try {
      const data = await this.request(`/parts/${this.partId}/update_locked_operation`, "PATCH", {
        position,
        operation_text: text
      })

      if (!data.success) throw new Error("Save failed")

      textarea.dataset.originalValue = text
      textarea.style.backgroundColor = "#f0fdf4" // success (light green)
      setTimeout(() => (textarea.style.backgroundColor = ""), 1000)
    } catch (error) {
      console.error("Error saving operation text:", error)
      textarea.style.backgroundColor = "#fef2f2" // error (light red)
      setTimeout(() => (textarea.style.backgroundColor = ""), 2000)
    }
  }
}
