// app/javascript/controllers/ai_assistant_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "input", "messages", "button", "sendBtn", "spinner", "fileInput", "filePreview"]

  connect() {
    this.messages = []
    this.isOpen = false
    this.pendingFile = null
    this.pollInterval = null
  }

  disconnect() {
    this.stopPolling()
  }

  toggle() { this.isOpen ? this.close() : this.open() }

  open() {
    this.isOpen = true
    this.panelTarget.classList.remove("hidden")
    this.panelTarget.classList.add("flex")
    this.inputTarget.focus()
    this.scrollToBottom()
  }

  close() {
    this.isOpen = false
    this.panelTarget.classList.add("hidden")
    this.panelTarget.classList.remove("flex")
  }

  // ── File handling ─────────────────────────────────────────────────────

  triggerFileUpload() { this.fileInputTarget.click() }

  async handleFileChange(event) {
    const file = event.target.files[0]
    if (!file) return

    const allowed = ["image/jpeg", "image/png", "image/gif", "image/webp", "application/pdf"]
    if (!allowed.includes(file.type)) {
      this.addMessage("error", "Only images (JPEG, PNG, GIF, WEBP) and PDFs are supported.")
      event.target.value = ""
      return
    }
    if (file.size > 10 * 1024 * 1024) {
      this.addMessage("error", "File too large — maximum 10MB.")
      event.target.value = ""
      return
    }

    const base64 = await this.readFileAsBase64(file)
    this.pendingFile = { base64, mediaType: file.type, name: file.name }
    this.filePreviewTarget.classList.remove("hidden")
    this.filePreviewTarget.querySelector("[data-filename]").textContent = file.name
    event.target.value = ""
  }

  removePendingFile() {
    this.pendingFile = null
    this.filePreviewTarget.classList.add("hidden")
    this.filePreviewTarget.querySelector("[data-filename]").textContent = ""
  }

  readFileAsBase64(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader()
      reader.onload  = () => resolve(reader.result.split(",")[1])
      reader.onerror = reject
      reader.readAsDataURL(file)
    })
  }

  // ── Send ──────────────────────────────────────────────────────────────

  async send() {
    const text = this.inputTarget.value.trim()
    if ((!text && !this.pendingFile) || this.sending) return

    this.inputTarget.value = ""

    let userContent
    let userDisplayText = text || "📎 File attached"

    if (this.pendingFile) {
      const parts = []
      if (this.pendingFile.mediaType === "application/pdf") {
        parts.push({ type: "document", source: { type: "base64", media_type: "application/pdf", data: this.pendingFile.base64 } })
      } else {
        parts.push({ type: "image", source: { type: "base64", media_type: this.pendingFile.mediaType, data: this.pendingFile.base64 } })
      }
      if (text) parts.push({ type: "text", text })
      userContent    = parts
      userDisplayText = (text ? text + " " : "") + `📎 ${this.pendingFile.name}`
      this.removePendingFile()
    } else {
      userContent = text
    }

    this.addMessage("user", userDisplayText)
    this.messages.push({ role: "user", content: userContent })
    this.setSending(true)

    try {
      const csrf = document.querySelector('meta[name="csrf-token"]')?.content
      const res  = await fetch("/ai_assistant/chat", {
        method:  "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
        body:    JSON.stringify({ messages: this.messages })
      })

      const data = await res.json()

      if (data.error) {
        this.addMessage("error", data.error)
        this.setSending(false)
      } else {
        // Got a request_id — start polling
        this.startPolling(data.request_id)
      }
    } catch (err) {
      this.addMessage("error", "Network error — please try again.")
      this.setSending(false)
    }
  }

  // ── Polling ───────────────────────────────────────────────────────────

  startPolling(requestId) {
    this.pollInterval = setInterval(() => this.checkStatus(requestId), 2000)
  }

  stopPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval)
      this.pollInterval = null
    }
  }

  async checkStatus(requestId) {
    try {
      const res  = await fetch(`/ai_assistant/status/${requestId}`)
      const data = await res.json()

      if (data.status === "complete") {
        this.stopPolling()
        this.messages.push({ role: "assistant", content: data.response })
        this.addMessage("assistant", data.response)
        this.setSending(false)
      } else if (data.status === "error") {
        this.stopPolling()
        this.addMessage("error", data.error || "Something went wrong.")
        this.setSending(false)
      }
      // if still "pending", just keep polling
    } catch (err) {
      this.stopPolling()
      this.addMessage("error", "Lost connection while waiting for response.")
      this.setSending(false)
    }
  }

  handleKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.send()
    }
  }

  clearHistory() {
    this.stopPolling()
    this.messages = []
    this.pendingFile = null
    this.filePreviewTarget.classList.add("hidden")
    this.messagesTarget.innerHTML = this.emptyStateHTML()
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  addMessage(role, text) {
    const placeholder = this.messagesTarget.querySelector("[data-placeholder]")
    if (placeholder) placeholder.remove()

    const wrapper = document.createElement("div")
    wrapper.classList.add("flex", role === "user" ? "justify-end" : "justify-start", "mb-3")

    const bubble = document.createElement("div")
    bubble.classList.add("max-w-[85%]", "rounded-xl", "px-3", "py-2", "text-sm", "leading-relaxed", "whitespace-pre-wrap")

    if (role === "user") {
      bubble.classList.add("bg-blue-600", "text-white", "rounded-br-sm")
    } else if (role === "error") {
      bubble.classList.add("bg-red-50", "text-red-700", "border", "border-red-200", "rounded-bl-sm")
    } else {
      bubble.classList.add("bg-white", "text-gray-800", "border", "border-gray-200", "rounded-bl-sm", "shadow-sm")
    }

    bubble.textContent = text
    wrapper.appendChild(bubble)
    this.messagesTarget.appendChild(wrapper)
    this.scrollToBottom()
  }

  setSending(state) {
    this.sending = state
    this.sendBtnTarget.disabled = state
    this.spinnerTarget.classList.toggle("hidden", !state)

    if (state) {
      const indicator = document.createElement("div")
      indicator.id = "typing-indicator"
      indicator.classList.add("flex", "justify-start", "mb-3")
      indicator.innerHTML = `
        <div class="bg-white border border-gray-200 rounded-xl rounded-bl-sm px-3 py-2 shadow-sm">
          <div class="flex space-x-1 items-center h-4">
            <div class="w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce" style="animation-delay:0ms"></div>
            <div class="w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce" style="animation-delay:150ms"></div>
            <div class="w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce" style="animation-delay:300ms"></div>
          </div>
        </div>
      `
      this.messagesTarget.appendChild(indicator)
      this.scrollToBottom()
    } else {
      document.getElementById("typing-indicator")?.remove()
    }
  }

  scrollToBottom() { this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight }

  emptyStateHTML() {
    return `<div data-placeholder class="flex flex-col items-center justify-center h-full text-gray-400 text-sm gap-2">
      <svg xmlns="http://www.w3.org/2000/svg" class="w-8 h-8 opacity-40" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"/>
      </svg>
      <p>Ask me anything about HAMS data</p>
    </div>`
  }
}
