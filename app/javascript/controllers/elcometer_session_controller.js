// app/javascript/controllers/elcometer_session_controller.js
//
// Single shared owner of the Elcometer connection for an entire release
// note's / process record's Thickness Measurements section.
//
// TRANSPORTS
//   serial    - Web Serial. Cabled RS232/USB, or a Bluetooth Classic (SPP)
//               gauge that Windows has paired as an outgoing COM port.
//   bluetooth - Web Bluetooth (BLE / "Bluetooth Smart"). Direct radio link to
//               the gauge, no pairing in Windows required.
// Both feed the SAME line buffer -> processLine -> routeReading, so sinks,
// routing and the banner are transport-agnostic.
//
// "Sinks" are the elcometer (standard anodic) and nadcap-sampling controllers.
// They register themselves with this session and implement a small interface:
//   sinkLabel()        -> string for the banner
//   acceptsReadings()  -> true if it can take another reading right now
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
// ENP batches are manual micrometer entry and never register here.

import { Controller } from "@hotwired/stimulus"

const RESUME_KEY = "elcometer-session-resume"        // "serial" | "bluetooth"
const RESUME_BLE_ID = "elcometer-session-ble-id"     // Web Bluetooth device id

// Candidate BLE profiles, tried in order. Most instrument BLE links are one of
// these transparent-serial services; the gauge streams the same ASCII it puts
// on the wire. If your meter uses its own service, set it on the session
// element instead of editing this list:
//   data-elcometer-session-ble-service-value="xxxxxxxx-...."
//   data-elcometer-session-ble-notify-value="xxxxxxxx-...."
// (see findNotifyCharacteristic below for how to discover them).
const BLE_PROFILES = [
  { name: "Nordic UART",       service: "6e400001-b5a3-f393-e0a9-e50e24dcca9e", notify: "6e400003-b5a3-f393-e0a9-e50e24dcca9e" },
  { name: "HM-10 / BLE serial", service: 0xffe0, notify: 0xffe1 },
  { name: "Generic serial",     service: 0xfff0, notify: 0xfff1 },
  { name: "Device information", service: 0x180a, notify: null }
]

// BLE notifications often arrive without a trailing newline, so a packet that
// hasn't been completed by one is treated as a whole line after this long.
const BLE_FLUSH_MS = 150

export default class extends Controller {
  static targets = ["connectButton", "bluetoothButton", "stopButton", "status"]

  static values = {
    bleService: String,     // optional: force a service UUID
    bleNotify: String,      // optional: force a notify characteristic UUID
    bleNamePrefix: String   // optional: filter the chooser, e.g. "Elcometer"
  }

  connect() {
    this.transport = null      // "serial" | "bluetooth"
    this.port = null
    this.reader = null
    this.device = null
    this.characteristic = null
    this.isReading = false
    this.buffer = ""
    this.flushTimer = null
    this.preferredSink = null
    this._onBleDisconnect = this.handleBleDisconnect.bind(this)
    this._onBleValue = this.handleBleValue.bind(this)

    // Adopt this session as the element's owner and pick up any sinks that
    // connected before us (Stimulus connect order is not guaranteed).
    this.element.elcometerSession = this
    this.sinks = this.element._elcometerPendingSinks || []
    this.element._elcometerPendingSinks = null
    this.sinks.forEach((s) => { s.session = this })
    this.sortSinks()

    this.hasSerial = "serial" in navigator
    this.hasBluetooth = "bluetooth" in navigator

    if (this.hasConnectButtonTarget && !this.hasSerial) this.connectButtonTarget.classList.add("hidden")
    if (this.hasBluetoothButtonTarget && !this.hasBluetooth) this.bluetoothButtonTarget.classList.add("hidden")

    if (!this.hasSerial && !this.hasBluetooth) {
      this.renderStatus("This browser can't talk to the meter — use Chrome or Edge. Manual entry still works.", "warn")
      return
    }

    this.updateBanner()

    // The process record reloads on every save / sign-off, which tears the page
    // (and this controller) down. If the operator had the meter connected, pick
    // it straight back up so one Connect click lasts the whole WO.
    const resume = sessionStorage.getItem(RESUME_KEY)
    if (resume === "serial" || resume === "1") this.autoResumeSerial()
    if (resume === "bluetooth") this.autoResumeBluetooth()
  }

  disconnect() {
    this.closeTransport()
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

  firstAvailableSink() {
    return this.sinks.find((s) => s.acceptsReadings && s.acceptsReadings()) || null
  }

  readyToConnect() {
    if (this.firstAvailableSink()) return true
    this.renderStatus("Nothing to measure yet — set up a batch (and parts-per-batch for NADCAP) first.", "warn")
    return false
  }

  // ── Serial transport ──────────────────────────────────────────────────────

  async connectElcometer() {
    if (!this.hasSerial) {
      this.renderStatus("Web Serial isn't available in this browser — try Bluetooth.", "warn")
      return
    }
    if (!this.readyToConnect()) return

    try {
      // Reuse a previously-granted port when there's exactly one, so the browser's
      // device chooser does not reappear. Fall back to the chooser otherwise.
      const granted = await navigator.serial.getPorts()
      const port = (granted && granted.length === 1) ? granted[0] : await navigator.serial.requestPort()
      await this.openPort(port)
    } catch (err) {
      if (err && err.name === "NotFoundError") {
        this.renderStatus("No device selected.", "warn")
      } else {
        this.renderStatus(`Connection error: ${err && err.message}`, "error")
      }
      console.error("Elcometer session serial connect error:", err)
    }
  }

  async autoResumeSerial() {
    // Sinks register asynchronously; give them a tick before checking capacity.
    await new Promise((r) => setTimeout(r, 50))
    if (!this.firstAvailableSink()) return
    try {
      const granted = await navigator.serial.getPorts()
      if (!granted || granted.length !== 1) return
      await this.openPort(granted[0])
    } catch (err) {
      console.warn("Elcometer serial auto-resume skipped:", err)
    }
  }

  async openPort(port) {
    this.port = port
    await this.port.open({ baudRate: 9600, dataBits: 8, stopBits: 1, parity: "none" })
    this.transport = "serial"
    this.isReading = true
    this.buffer = ""
    sessionStorage.setItem(RESUME_KEY, "serial")
    this.showConnected()
    this.startReading()
  }

  async startReading() {
    try {
      const decoder = new TextDecoderStream()
      this.port.readable.pipeTo(decoder.writable)
      this.reader = decoder.readable.getReader()

      while (this.isReading) {
        const { value, done } = await this.reader.read()
        if (done) break
        this.ingest(value)
      }
    } catch (err) {
      if (this.isReading) {
        this.renderStatus(`Reading error: ${err && err.message}`, "error")
        console.error("Elcometer session read error:", err)
      }
    }
  }

  // ── Bluetooth (BLE) transport ─────────────────────────────────────────────

  candidateServices() {
    const list = BLE_PROFILES.map((p) => p.service)
    if (this.bleServiceValue) list.unshift(this.bleServiceValue.toLowerCase())
    return list
  }

  async connectBluetooth() {
    if (!this.hasBluetooth) {
      this.renderStatus("Web Bluetooth isn't available in this browser — use Chrome or Edge over HTTPS.", "warn")
      return
    }
    if (!this.readyToConnect()) return

    try {
      this.renderStatus("Choose the meter in the browser's Bluetooth dialog…", "idle")
      const prefix = this.bleNamePrefixValue
      const device = await navigator.bluetooth.requestDevice(
        prefix
          ? { filters: [{ namePrefix: prefix }], optionalServices: this.candidateServices() }
          : { acceptAllDevices: true, optionalServices: this.candidateServices() }
      )
      await this.openBleDevice(device)
    } catch (err) {
      if (err && (err.name === "NotFoundError" || err.name === "AbortError")) {
        this.renderStatus("No meter selected.", "warn")
      } else {
        this.renderStatus(`Bluetooth error: ${err && err.message}`, "error")
      }
      console.error("Elcometer session bluetooth connect error:", err)
    }
  }

  // Chrome only returns already-permitted devices from getDevices(), and only
  // where the persistent-permissions backend is enabled. When it isn't, the
  // operator clicks Bluetooth once after each reload — everything else still works.
  async autoResumeBluetooth() {
    await new Promise((r) => setTimeout(r, 50))
    if (!this.firstAvailableSink()) return
    if (!navigator.bluetooth.getDevices) return
    try {
      const id = sessionStorage.getItem(RESUME_BLE_ID)
      const devices = await navigator.bluetooth.getDevices()
      const device = devices.find((d) => d.id === id) || (devices.length === 1 ? devices[0] : null)
      if (!device) return
      await this.openBleDevice(device)
    } catch (err) {
      console.warn("Elcometer bluetooth auto-resume skipped:", err)
    }
  }

  async openBleDevice(device) {
    this.device = device
    device.removeEventListener("gattserverdisconnected", this._onBleDisconnect)
    device.addEventListener("gattserverdisconnected", this._onBleDisconnect)

    this.renderStatus(`Connecting to ${this.escape(device.name || "meter")}…`, "idle")
    const server = await device.gatt.connect()
    const characteristic = await this.findNotifyCharacteristic(server)
    if (!characteristic) {
      await device.gatt.disconnect()
      this.renderStatus(
        "Connected, but no readings channel found on this meter. Check the console for the services it exposes.",
        "error"
      )
      return
    }

    this.characteristic = characteristic
    characteristic.removeEventListener("characteristicvaluechanged", this._onBleValue)
    characteristic.addEventListener("characteristicvaluechanged", this._onBleValue)
    await characteristic.startNotifications()

    this.transport = "bluetooth"
    this.isReading = true
    this.buffer = ""
    sessionStorage.setItem(RESUME_KEY, "bluetooth")
    if (device.id) sessionStorage.setItem(RESUME_BLE_ID, device.id)
    this.showConnected()
  }

  // Tries the configured/known profiles, then sweeps every service the browser
  // will expose and takes the first notifying characteristic. Everything it
  // finds is logged, so `console` on a real gauge tells you the UUIDs to pin
  // via data-elcometer-session-ble-service-value / -ble-notify-value.
  // (chrome://bluetooth-internals -> Devices -> Inspect lists them all,
  // including services the page has not been granted.)
  async findNotifyCharacteristic(server) {
    const profiles = this.bleServiceValue
      ? [{ name: "configured", service: this.bleServiceValue.toLowerCase(), notify: (this.bleNotifyValue || "").toLowerCase() || null }, ...BLE_PROFILES]
      : BLE_PROFILES

    for (const profile of profiles) {
      let service
      try {
        service = await server.getPrimaryService(profile.service)
      } catch (err) {
        continue
      }
      if (profile.notify) {
        try {
          const c = await service.getCharacteristic(profile.notify)
          if (c.properties.notify || c.properties.indicate) {
            console.info(`Elcometer BLE: using ${profile.name} ${c.uuid}`)
            return c
          }
        } catch (err) { /* fall through to the sweep below */ }
      }
      const found = await this.sweepService(service)
      if (found) return found
    }

    try {
      for (const service of await server.getPrimaryServices()) {
        const found = await this.sweepService(service)
        if (found) return found
      }
    } catch (err) {
      console.warn("Elcometer BLE: service sweep failed:", err)
    }
    return null
  }

  async sweepService(service) {
    try {
      const chars = await service.getCharacteristics()
      console.info(
        `Elcometer BLE: service ${service.uuid} ->`,
        chars.map((c) => `${c.uuid} [${Object.keys(c.properties).filter((k) => c.properties[k]).join(",")}]`)
      )
      const c = chars.find((ch) => ch.properties.notify || ch.properties.indicate)
      if (c) return c
    } catch (err) {
      console.warn(`Elcometer BLE: could not read ${service.uuid}:`, err)
    }
    return null
  }

  handleBleValue(event) {
    const view = event.target.value
    const text = new TextDecoder().decode(view)
    // Non-printable payload means the meter is sending a binary protocol
    // rather than its ASCII stream — dump it once so the format can be decoded.
    if (!/^[\x09\x0a\x0d\x20-\x7e]*$/.test(text)) {
      if (!this._loggedBinary) {
        this._loggedBinary = true
        const hex = Array.from(new Uint8Array(view.buffer)).map((b) => b.toString(16).padStart(2, "0")).join(" ")
        console.warn("Elcometer BLE: binary payload, first packet:", hex)
      }
      return
    }
    this.ingest(text)
  }

  handleBleDisconnect() {
    if (!this.isReading || this.transport !== "bluetooth") return
    this.renderStatus("Meter dropped the Bluetooth link — reconnecting…", "warn")
    this.reconnectBle(1)
  }

  async reconnectBle(attempt) {
    if (!this.isReading || !this.device) return
    if (attempt > 3) {
      this.isReading = false
      this.showDisconnected()
      this.renderStatus("Bluetooth link lost. Press Bluetooth to reconnect — readings so far are kept.", "warn")
      return
    }
    await new Promise((r) => setTimeout(r, 500 * attempt))
    try {
      await this.openBleDevice(this.device)
    } catch (err) {
      console.warn(`Elcometer BLE reconnect attempt ${attempt} failed:`, err)
      this.reconnectBle(attempt + 1)
    }
  }

  // ── Line assembly / parsing ───────────────────────────────────────────────

  ingest(text) {
    this.buffer += text
    const lines = this.buffer.split(/\r?\n/)
    this.buffer = lines.pop()
    for (const line of lines) this.processLine(line)

    // BLE packets frequently carry one reading with no terminator; flush a
    // quiet buffer so those aren't left waiting for a newline that never comes.
    if (this.transport === "bluetooth") {
      clearTimeout(this.flushTimer)
      if (this.buffer.trim()) {
        this.flushTimer = setTimeout(() => {
          const line = this.buffer
          this.buffer = ""
          this.processLine(line)
        }, BLE_FLUSH_MS)
      }
    }
  }

  processLine(line) {
    const value = this.parseReading(line)
    if (value === null) return
    this.routeReading(Math.round(value * 10) / 10)
  }

  // "123.4 um" / "123.4µm" on either transport; a bare number is accepted only
  // over BLE, where the unit is often dropped from the packet. Serial keeps the
  // stricter rule so a fragmented frame can never be read as a bogus reading.
  parseReading(line) {
    const united = line.match(/(-?[\d.]+)\s*(?:um|µm|μm)\b/i)
    const match = united || (this.transport === "bluetooth" ? line.trim().match(/^(-?[\d.]+)$/) : null)
    if (!match) return null
    const value = parseFloat(match[1])
    if (isNaN(value) || value <= 0 || value > 10000) return null
    return value
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

  // ── Teardown ──────────────────────────────────────────────────────────────

  // Operator pressed Disconnect: forget the resume intent too.
  stopReading() {
    sessionStorage.removeItem(RESUME_KEY)
    sessionStorage.removeItem(RESUME_BLE_ID)
    return this.closeTransport()
  }

  async closeTransport() {
    this.isReading = false
    clearTimeout(this.flushTimer)
    try {
      if (this.characteristic) {
        this.characteristic.removeEventListener("characteristicvaluechanged", this._onBleValue)
        try { await this.characteristic.stopNotifications() } catch (err) { /* already gone */ }
        this.characteristic = null
      }
      if (this.device) {
        this.device.removeEventListener("gattserverdisconnected", this._onBleDisconnect)
        if (this.device.gatt && this.device.gatt.connected) this.device.gatt.disconnect()
        this.device = null
      }
      if (this.reader) { await this.reader.cancel(); this.reader = null }
      if (this.port) { await this.port.close(); this.port = null }
    } catch (err) {
      console.error("Elcometer session stop error:", err)
    }
    this.transport = null
    this.showDisconnected()
  }

  // ── Banner / status ─────────────────────────────────────────────────────

  showConnected() {
    if (this.hasConnectButtonTarget) this.connectButtonTarget.classList.add("hidden")
    if (this.hasBluetoothButtonTarget) this.bluetoothButtonTarget.classList.add("hidden")
    if (this.hasStopButtonTarget) this.stopButtonTarget.classList.remove("hidden")
    this.updateBanner()
  }

  showDisconnected() {
    if (this.hasConnectButtonTarget && this.hasSerial) this.connectButtonTarget.classList.remove("hidden")
    if (this.hasBluetoothButtonTarget && this.hasBluetooth) this.bluetoothButtonTarget.classList.remove("hidden")
    if (this.hasStopButtonTarget) this.stopButtonTarget.classList.add("hidden")
    this.updateBanner()
  }

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
        this.renderStatus("Connect the Elcometer — by cable or Bluetooth — to auto-fill readings across every batch.", "idle")
      } else {
        this.renderStatus(`Ready — ${total.done}/${total.expected} readings recorded. Connect to continue.`, "idle")
      }
      return
    }

    const target = (this.preferredSink && this.preferredSink.acceptsReadings())
      ? this.preferredSink
      : this.firstAvailableSink()

    const via = this.transport === "bluetooth" ? "Bluetooth" : "cable"

    if (!target) {
      this.renderStatus(`All readings captured — ${total.done}/${total.expected}. Disconnect when ready.`, "ok")
      return
    }

    const slot = target.nextSlotLabel ? target.nextSlotLabel() : ""
    const label = this.escape(target.sinkLabel())
    this.renderStatus(
      `<span class="font-semibold">Now filling:</span> ${label}` +
      `${slot ? " · " + this.escape(slot) : ""} ` +
      `<span class="opacity-60">(total ${total.done}/${total.expected} · ${via})</span>`,
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
