// app/javascript/controllers/ai_assistant_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "input", "messages", "button", "sendBtn", "spinner"]

  connect() {
    this.messages = [] // conversation history
    this.isOpen = false
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.isOpen = true
    this.panelTarget.classList.remove("hidden")
    this.panelTarget.classList.add("flex")
    this.inputTarget.focus()
    // Scroll to bottom of messages
    this.scrollToBottom()
  }

  close() {
    this.isOpen = false
    this.panelTarget.classList.add("hidden")
    this.panelTarget.classList.remove("flex")
  }

  async send() {
    const text = this.inputTarget.value.trim()
    if (!text || this.sending) return

    this.inputTarget.value = ""
    this.addMessage("user", text)
    this.messages.push({ role: "user", content: text })

    this.setSending(true)

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

      const response = await fetch("/ai_assistant/chat", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({ messages: this.messages })
      })

      const data = await response.json()

      if (data.error) {
        this.addMessage("error", data.error)
      } else {
        const assistantText = data.response
        this.messages.push({ role: "assistant", content: assistantText })
        this.addMessage("assistant", assistantText)
      }
    } catch (err) {
      this.addMessage("error", "Network error — please try again.")
    } finally {
      this.setSending(false)
    }
  }

  handleKeydown(event) {
    // Send on Enter, new line on Shift+Enter
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.send()
    }
  }

  clearHistory() {
    this.messages = []
    this.messagesTarget.innerHTML = this.emptyStateHTML()
  }

  // ── Private helpers ──────────────────────────────────────────────────

  addMessage(role, text) {
    // Remove empty state placeholder if present
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
      // Show typing indicator
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

  scrollToBottom() {
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }

  emptyStateHTML() {
    return `<div data-placeholder class="flex flex-col items-center justify-center h-full text-gray-400 text-sm gap-2">
      <svg xmlns="http://www.w3.org/2000/svg" class="w-8 h-8 opacity-40" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"/>
      </svg>
      <p>Ask me anything about HAMS data</p>
    </div>`
  }
}
