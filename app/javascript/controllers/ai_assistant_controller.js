// app/javascript/controllers/ai_assistant_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "input", "messages", "button", "sendBtn", "spinner", "fileInput", "filePreview", "resizeHandle"]

  connect() {
    this.messages = []
    this.isOpen = false
    this.pendingFiles = []
    this.pollTimeout = null
    this.polling = false
    this.pollFailures = 0
    this.currentRequestId = null

    // Restore user's preferred panel height, if set
    const saved = localStorage.getItem("aiAssistantHeight")
    if (saved) this.panelTarget.style.height = `${saved}px`

    // Bind once so we can add/remove the same reference
    this._onResize     = this.onResize.bind(this)
    this._endResize    = this.endResize.bind(this)
    this._onVisibility = () => {
      if (document.visibilityState === "visible" && this.polling && this.currentRequestId) {
        // Tab came back — don't wait up to 2s for the next scheduled poll
        if (this.pollTimeout) { clearTimeout(this.pollTimeout); this.pollTimeout = null }
        this.checkStatus(this.currentRequestId)
      }
    }
    document.addEventListener("visibilitychange", this._onVisibility)
  }

  disconnect() {
    this.stopPolling()
    document.removeEventListener("visibilitychange", this._onVisibility)
  }

  toggle() { this.isOpen ? this.close() : this.open() }

  open() {
    this.isOpen = true
    this.panelTarget.classList.remove("hidden")
    this.panelTarget.classList.add("flex")
    this.buttonTarget.classList.add("hidden")
    this.inputTarget.focus()
    this.scrollToBottom()
  }

  close() {
    this.isOpen = false
    this.panelTarget.classList.add("hidden")
    this.panelTarget.classList.remove("flex")
    this.buttonTarget.classList.remove("hidden")
  }

  // ── Resize ────────────────────────────────────────────────────────────

  startResize(event) {
    event.preventDefault()
    this.resizing = true
    this.startY = event.clientY
    this.startHeight = this.panelTarget.offsetHeight
    document.addEventListener("pointermove", this._onResize)
    document.addEventListener("pointerup",   this._endResize)
    document.addEventListener("pointercancel", this._endResize)
    document.body.style.userSelect = "none"
  }

  onResize(event) {
    if (!this.resizing) return
    const delta = this.startY - event.clientY           // drag up = grow
    const max   = window.innerHeight - 16               // leave 16px gap at top
    const min   = 240
    const next  = Math.min(Math.max(this.startHeight + delta, min), max)
    this.panelTarget.style.height = `${next}px`
  }

  endResize() {
    if (!this.resizing) return
    this.resizing = false
    document.removeEventListener("pointermove", this._onResize)
    document.removeEventListener("pointerup",   this._endResize)
    document.removeEventListener("pointercancel", this._endResize)
    document.body.style.userSelect = ""
    localStorage.setItem("aiAssistantHeight", this.panelTarget.offsetHeight)
    this.scrollToBottom()
  }

  // ── File handling ─────────────────────────────────────────────────────

  triggerFileUpload() { this.fileInputTarget.click() }

  async handleFileChange(event) {
    const files = Array.from(event.target.files)
    if (!files.length) return

    const allowed = ["image/jpeg", "image/png", "image/gif", "image/webp", "application/pdf"]

    for (const file of files) {
      if (!allowed.includes(file.type)) {
        this.addMessage("error", `${file.name}: Only images (JPEG, PNG, GIF, WEBP) and PDFs are supported.`)
        continue
      }
      if (file.size > 10 * 1024 * 1024) {
        this.addMessage("error", `${file.name}: File too large — maximum 10MB.`)
        continue
      }

      const base64 = await this.readFileAsBase64(file)
      this.pendingFiles.push({ base64, mediaType: file.type, name: file.name })
    }

    this.renderFilePreviews()
    event.target.value = ""
  }

  removePendingFileAt(index) {
    this.pendingFiles.splice(index, 1)
    this.renderFilePreviews()
  }

  removePendingFile() {
    this.pendingFiles = []
    this.renderFilePreviews()
  }

  renderFilePreviews() {
    const container = this.filePreviewTarget
    container.innerHTML = ""

    if (this.pendingFiles.length === 0) {
      container.classList.add("hidden")
      return
    }

    container.classList.remove("hidden")
    this.pendingFiles.forEach((file, index) => {
      const badge = document.createElement("div")
      badge.classList.add("flex", "items-center", "gap-1.5", "bg-blue-50", "border", "border-blue-200", "rounded-lg", "px-2", "py-1", "text-xs", "text-blue-700")
      badge.innerHTML = `
        <svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13"/>
        </svg>
        <span class="truncate max-w-[120px]">${file.name}</span>
      `
      const removeBtn = document.createElement("button")
      removeBtn.classList.add("shrink-0", "hover:text-red-500", "transition-colors")
      removeBtn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/></svg>`
      removeBtn.addEventListener("click", () => this.removePendingFileAt(index))
      badge.appendChild(removeBtn)
      container.appendChild(badge)
    })
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
    if ((!text && !this.pendingFiles.length) || this.sending) return

    // Belt-and-braces: kill any orphaned poller from a previous send
    this.stopPolling()

    this.inputTarget.value = ""

    let userContent
    let userDisplayText = text || "📎 Files attached"

    if (this.pendingFiles.length > 0) {
      const parts = []
      const fileNames = []
      for (const file of this.pendingFiles) {
        if (file.mediaType === "application/pdf") {
          parts.push({ type: "document", source: { type: "base64", media_type: "application/pdf", data: file.base64 } })
        } else {
          parts.push({ type: "image", source: { type: "base64", media_type: file.mediaType, data: file.base64 } })
        }
        fileNames.push(file.name)
      }
      if (text) parts.push({ type: "text", text })
      userContent    = parts
      userDisplayText = (text ? text + " " : "") + `📎 ${fileNames.join(", ")}`
      this.pendingFiles = []
      this.renderFilePreviews()
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
    this.currentRequestId = requestId
    this.polling = true
    this.pollFailures = 0
    this.scheduleNextPoll(requestId)
  }

  scheduleNextPoll(requestId) {
    if (!this.polling || requestId !== this.currentRequestId) return
    this.pollTimeout = setTimeout(() => this.checkStatus(requestId), 2000)
  }

  stopPolling() {
    this.polling = false
    this.currentRequestId = null
    if (this.pollTimeout) {
      clearTimeout(this.pollTimeout)
      this.pollTimeout = null
    }
  }

  async checkStatus(requestId) {
    // Stale-poll guard: caller may have been superseded or cancelled
    if (!this.polling || requestId !== this.currentRequestId) return

    try {
      const res = await fetch(`/ai_assistant/status/${requestId}`)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()

      // Re-check: state may have changed while the fetch was in flight
      if (!this.polling || requestId !== this.currentRequestId) return

      this.pollFailures = 0

      if (data.status === "complete") {
        this.stopPolling()
        this.messages.push({ role: "assistant", content: data.response })
        this.addMessage("assistant", data.response)
        this.setSending(false)
      } else if (data.status === "error") {
        this.stopPolling()
        this.addMessage("error", data.error || "Something went wrong.")
        this.setSending(false)
      } else {
        // still "pending" — schedule next poll only after this one returned
        this.scheduleNextPoll(requestId)
      }
    } catch (err) {
      // Mobile networks blip. Tolerate ~30s of consecutive failures before
      // giving up — the Sidekiq job is usually still running and will finish.
      this.pollFailures += 1
      if (this.pollFailures >= 15) {
        this.stopPolling()
        this.addMessage("error", "Lost connection — the job may still be running. Refresh in a moment to see the result.")
        this.setSending(false)
      } else {
        this.scheduleNextPoll(requestId)
      }
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
    this.pendingFiles = []
    this.renderFilePreviews()
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

    // Assistant replies are rendered as sanitised HTML so links are clickable.
    // User and error bubbles stay as plain text — no markup is ever trusted from them.
    if (role === "assistant") {
      bubble.innerHTML = this.renderRich(text)
    } else {
      bubble.textContent = text
    }

    wrapper.appendChild(bubble)
    this.messagesTarget.appendChild(wrapper)
    this.scrollToBottom()
  }

  // ── Safe rich rendering (links only) ──────────────────────────────────

  // Escape-first, then linkify. Order matters: we pull Markdown links out into
  // placeholders BEFORE escaping so their syntax survives, escape everything
  // (neutralising any HTML/script the model may have emitted), linkify bare URLs
  // in the now-safe text, then restore the Markdown links as anchors.
  renderRich(text) {
    const links = []
    const PH = (i) => `\uE000${i}\uE001` // private-use sentinels, never in real text

    // 1. Extract Markdown links [label](http(s)://… or /relative)
    let work = String(text).replace(
      /\[([^\]]+)\]\((https?:\/\/[^\s)]+|\/[^\s)]+)\)/g,
      (_m, label, url) => {
        const i = links.push({ label, url }) - 1
        return PH(i)
      }
    )

    // 2. Escape all remaining text
    work = this.escapeHtml(work)

    // 3. Linkify bare URLs left in the escaped text
    work = work.replace(/(https?:\/\/[^\s<]+)/g, (m) => {
      const href = m.replace(/&amp;/g, "&")  // undo escaping for the href value only
      return this.anchor(href, m)
    })

    // 4. Restore Markdown links (label is escaped; href is validated)
    work = work.replace(/\uE000(\d+)\uE001/g, (_m, i) => {
      const { label, url } = links[parseInt(i, 10)]
      return this.anchor(url, this.escapeHtml(label))
    })

    return work
  }

  anchor(href, innerHtml) {
    const safeHref = /^(https?:\/\/|\/)/.test(href) ? href : "#"
    return `<a href="${this.escapeAttr(safeHref)}" target="_blank" rel="noopener noreferrer" ` +
           `class="underline text-blue-600 hover:text-blue-800 break-words">${innerHtml}</a>`
  }

  escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = String(str)
    return div.innerHTML
  }

  escapeAttr(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/"/g, "&quot;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
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
