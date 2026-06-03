// app/javascript/controllers/elcometer_session_controller.js
//
// Single shared owner of the Elcometer serial connection for an entire release
// note's Thickness Measurements section.
//
// The Web Serial API allows only ONE open connection and ONE reader per port, so
// individual batch controllers can no longer each own the port — that was why
// operators had to connect/stop once per film type and per batch. This session
// owns the port + read loop and routes each incoming reading to the active batch.
//
// "Sinks" are the elcometer (standard anodic) and nadcap-sampling controllers.
// They register themselves with this session and implement a small interface:
//   sinkLabel()        -> string for the banner
//   acceptsReadings()  -> true if it can take another serial reading right now
//   isComplete()       -> true if full
//   acceptReading(v)   -> place one reading; returns true if placed
//   progress()         -> { done, expected }
//   nextSlotLabel()    -> short label for where the next reading lands (optional)
//
// Routing = auto-advance with manual override:
//   - Readings fill the first VISIBLE batch (document order) that still has room.
//   - When a batch fills, the cursor rolls to the next automatically.
//   - Focusing/clicking inside a batch makes it the preferred target.
//
// ENP batches are manual micrometer entry (not on the serial stream) and never
// register here.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["connectButton", "stopButton", "status"]

  connect() {
    this.port = null
    this.reader = null
    this.isReading = false
    this.preferredSink = null

    // Adopt this session as the element's owner and pick up any sinks that
    // connected before us (Stimulus connect order is not guaranteed).
    this.element.elcometerSession = this
    this.sinks = this.element._elcometerPendingSinks || []
    this.element._elcometerPendingSinks = null
    this.sinks.forEach((s) => { s.session = this })
    this.sortSinks()

    if (!("serial" in navigator)) {
      this.renderStatus("Web Serial not supported — use Chrome or Edge. Manual entry still works.", "warn")
      if (this.hasConnectButtonTarget) this.connectButtonTarget.disabled = true
    } else {
      this.updateBanner()
    }
  }

  disconnect() {
    this.stopReading()
    if (this.element.elcometerSession === this) this.element.elcometerSession = null
  }

  // ── Sink registry ───────────────────────────────────────────────────────

  addSink(sink) {
    if (!this.sinks.includes(sink)) {
      this.sinks.push(sink)
      sink.session = this
      this.sortSinks()
      this.updateBanner()
    }
  }

  removeSink(sink) {
    this.sinks = this.sinks.filter((s) => s !== sink)
    if (this.preferredSink === sink) this.preferredSink = null
    this.updateBanner()
  }

  sortSinks() {
    this.sinks.sort((a, b) => {
      const pos = a.element.compareDocumentPosition(b.element)
      if (pos & Node.DOCUMENT_POSITION_FOLLOWING) return -1
      if (pos & Node.DOCUMENT_POSITION_PRECEDING) return 1
      return 0
    })
  }

  setPreferred(sink) {
    this.preferredSink = (sink && sink.acceptsReadings && sink.acceptsReadings()) ? sink : null
    this.updateBanner()
  }

  // Sinks call this after manual edits / capacity changes so the banner stays fresh.
  refresh() { this.updateBanner() }

  // ── Connection ────────────────────────────────────────────────────────────

  async connectElcometer() {
    if (!this.firstAvailableSink()) {
      this.renderStatus("Nothing to measure yet — set up a batch (and parts-per-batch for NADCAP) first.", "warn")
      return
    }

    try {
      // Reuse a previously-granted port when there's exactly one, so the browser's
      // device chooser does not reappear. Fall back to the chooser otherwise.
      const granted = await navigator.serial.getPorts()
      this.port = (granted && granted.length === 1) ? granted[0] : await navigator.serial.requestPort()

      await this.port.open({ baudRate: 9600, dataBits: 8, stopBits: 1, parity: "none" })

      this.isReading = true
      if (this.hasConnectButtonTarget) this.connectButtonTarget.classList.add("hidden")
      if (this.hasStopButtonTarget) this.stopButtonTarget.classList.remove("hidden")
      this.updateBanner()
      this.startReading()
    } catch (err) {
      if (err && err.name === "NotFoundError") {
        this.renderStatus("No device selected.", "warn")
      } else {
        this.renderStatus(`Connection error: ${err && err.message}`, "error")
      }
      console.error("Elcometer session connect error:", err)
    }
  }

  async startReading() {
    try {
      const decoder = new TextDecoderStream()
      this.port.readable.pipeTo(decoder.writable)
      this.reader = decoder.readable.getReader()

      let buffer = ""
      while (this.isReading) {
        const { value, done } = await this.reader.read()
        if (done) break
        buffer += value
        const lines = buffer.split("\n")
        buffer = lines.pop()
        for (const line of lines) this.processLine(line)
      }
    } catch (err) {
      if (this.isReading) {
        this.renderStatus(`Reading error: ${err && err.message}`, "error")
        console.error("Elcometer session read error:", err)
      }
    }
  }

  processLine(line) {
    const match = line.match(/\s*([\d.]+)\s*um/i)
    if (!match) return
    const value = parseFloat(match[1])
    if (isNaN(value) || value <= 0) return
    this.routeReading(Math.round(value * 10) / 10)
  }

  routeReading(value) {
    let target = (this.preferredSink && this.preferredSink.acceptsReadings())
      ? this.preferredSink
      : this.firstAvailableSink()

    let placed = target ? target.acceptReading(value) : false

    // Race / preferred-just-filled: retry against the next available sink.
    if (!placed) {
      target = this.firstAvailableSink()
      placed = target ? target.acceptReading(value) : false
    }

    if (!placed) {
      this.renderStatus("All batches full — reading ignored. Add a batch or disconnect.", "warn")
      return
    }

    if (this.preferredSink && !this.preferredSink.acceptsReadings()) this.preferredSink = null
    this.updateBanner()
  }

  firstAvailableSink() {
    return this.sinks.find((s) => s.acceptsReadings && s.acceptsReadings()) || null
  }

  async stopReading() {
    this.isReading = false
    try {
      if (this.reader) { await this.reader.cancel(); this.reader = null }
      if (this.port) { await this.port.close(); this.port = null }
    } catch (err) {
      console.error("Elcometer session stop error:", err)
    }
    if (this.hasConnectButtonTarget) this.connectButtonTarget.classList.remove("hidden")
    if (this.hasStopButtonTarget) this.stopButtonTarget.classList.add("hidden")
    this.updateBanner()
  }

  // ── Banner / status ─────────────────────────────────────────────────────

  totals() {
    return this.sinks.reduce((acc, s) => {
      const p = s.progress ? s.progress() : { done: 0, expected: 0 }
      acc.done += p.done
      acc.expected += p.expected
      return acc
    }, { done: 0, expected: 0 })
  }

  updateBanner() {
    if (!this.hasStatusTarget) return
    const total = this.totals()

    if (!this.isReading) {
      if (total.expected === 0) {
        this.renderStatus("Connect the Elcometer to auto-fill readings across every batch.", "idle")
      } else {
        this.renderStatus(`Ready — ${total.done}/${total.expected} readings recorded. Connect to continue.`, "idle")
      }
      return
    }

    const target = (this.preferredSink && this.preferredSink.acceptsReadings())
      ? this.preferredSink
      : this.firstAvailableSink()

    if (!target) {
      this.renderStatus(`All readings captured — ${total.done}/${total.expected}. Disconnect when ready.`, "ok")
      return
    }

    const slot = target.nextSlotLabel ? target.nextSlotLabel() : ""
    const label = this.escape(target.sinkLabel())
    this.renderStatus(
      `<span class="font-semibold">Now filling:</span> ${label}` +
      `${slot ? " · " + this.escape(slot) : ""} ` +
      `<span class="opacity-60">(total ${total.done}/${total.expected})</span>`,
      "live"
    )
  }

  renderStatus(html, kind) {
    if (!this.hasStatusTarget) return
    const styles = {
      idle:  "bg-gray-50 text-gray-600 border-gray-200",
      live:  "bg-blue-50 text-blue-800 border-blue-200",
      ok:    "bg-green-50 text-green-800 border-green-200",
      warn:  "bg-amber-50 text-amber-800 border-amber-200",
      error: "bg-red-50 text-red-700 border-red-200"
    }
    this.statusTarget.className = `flex-1 text-sm border rounded-md px-3 py-2 ${styles[kind] || styles.idle}`
    this.statusTarget.innerHTML = html
  }

  escape(str) {
    const div = document.createElement("div")
    div.textContent = String(str)
    return div.innerHTML
  }
}
