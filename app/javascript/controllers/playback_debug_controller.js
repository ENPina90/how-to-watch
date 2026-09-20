import { Controller } from "@hotwired/stimulus"

// A readout of what is happening to the player, for when a film misbehaves and nobody can
// say whose fault it is.
//
// It exists because the console cannot be used on this page. VidSrc loads
// `disable-devtool.js` on both its wrapper and its player, and on detecting an inspector
// it navigates its own document to `about:blank` (docs/guides/VIDSRC.md §7) -- so opening
// DevTools to watch a warmed VidSrc channel destroys the thing being watched and changes
// the experiment. Everything here therefore has to be readable with DevTools shut: it is
// written into the page, and kept in localStorage so it survives the reload it may be
// recording.
//
// The headline is the **spare verdict**, in the bar. Twenty seconds after a channel is
// warmed, cinema-navigation decides whether that second player stopped when it was told
// to; `stopped` is the ordinary case and `DROPPED` means it would not, so its frame was
// taken away before it could run a second film behind the first for two hours. How often
// each happens is the experiment (see STOP_DEADLINE in cinema_navigation_controller.js).
//
// The frame count is beside it as context, not as the alarm. Two frames is *correct* when
// the spare has stopped -- that is what warming is -- and reading the count alone as the
// fault was the first mistake this readout made about itself.
//
// One thing it cannot see: a player that speaks once, is told to stop, and then simply
// stops reporting while still playing. From outside a cross-origin frame that is
// indistinguishable from having obeyed. The documented failure (VIDSRC.md §6a) is a frame
// that never speaks at all, which is caught -- but if `stopped` verdicts keep turning up
// alongside a film that dies, this is the assumption to doubt first.
//
// It rides outside `#cinema-chrome`, so a move between entries does not replace it and one
// recording spans a whole evening. It rides *inside* the element that goes fullscreen, for
// the same reason the up-next card does: anything outside that element is not rendered at
// all while fullscreen, and a readout nobody can see during the two hours in question is
// no readout.
//
// Reached with `?debug=1` and by nothing else. The parameter does not survive a move --
// the address pushed afterwards is the server's -- but this element does, so the recording
// carries on regardless.

// Long enough that an evening is a few hundred lines rather than thousands, short enough
// to place a fault to the right half minute.
const TICK = 15000

// How much of the log to keep across reloads. A line is ~100 bytes, so this is well inside
// what localStorage will hold, and it is the last few hours rather than the first few.
const KEPT_LINES = 400
const STORE = "playbackDebug"

// The events worth finding at a glance, coloured in the readout. Each is something that
// can end a film rather than something that merely happened.
const LOUD = [
  "frame-reload", "reloaded", "back-forward", "discarded", "freeze", "offline",
  "spare-kept-playing",
]

export default class extends Controller {
  static targets = ["frames", "elapsed", "log", "heap", "history", "navigation", "verdict"]

  connect() {
    this.started = performance.now()
    this.listeners = []
    this.run = Math.random().toString(36).slice(2, 8)
    this.log = []

    this.drawStored()
    this.watchTheFrames()
    this.watchTheBrowser()
    this.watchTheChannel()

    const navigation = performance.getEntriesByType("navigation")[0]
    const how = navigation ? navigation.type : "unknown"
    if (this.hasNavigationTarget) this.navigationTarget.textContent = how

    this.record("boot", {
      how: how,
      entry: this.element.dataset.entry,
      adapter: this.element.dataset.adapter || "none",
      preload: this.element.dataset.preload,
      // What cinema-navigation asks itself before warming anything. A page that will not
      // warm cannot be the page that warmed too much, and this says which one you are on.
      warms: this.wouldWarm(),
      discarded: document.wasDiscarded === true,
      history: history.length,
      width: window.innerWidth,
      memoryGb: navigator.deviceMemory ?? null,
    })

    // Said on their own so they colour the readout. A reload is how a film starts again
    // from the beginning on a provider with no resume, and it is the first thing to rule
    // in or out.
    if (how === "reload") this.record("reloaded")
    if (how === "back_forward") this.record("back-forward")
    if (document.wasDiscarded === true) this.record("discarded")

    this.ticker = setInterval(() => this.tick(), TICK)
    this.painter = setInterval(() => this.paintCounts(), 1000)
    this.paintCounts()
  }

  disconnect() {
    clearInterval(this.ticker)
    clearInterval(this.painter)
    this.listeners.forEach(([target, event, handler, capture]) =>
      target.removeEventListener(event, handler, capture))
  }

  // ---- what is being watched ---------------------------------------------------------

  // Every frame in the stack, live or warmed, and every time one of them loads a document.
  //
  // Bound on the container in the capture phase rather than on the frames themselves: a
  // `load` event does not bubble, but it does pass through its ancestors on the way down,
  // and the frames come and go -- the live one is *replaced* when a warmed spare is
  // adopted. A listener on the container outlives all of that.
  watchTheFrames() {
    this.loads = {}
    const frames = document.getElementById("cinema-frames")
    if (!frames) return

    this.on(frames, "load", (event) => {
      const id = event.target.id || "unnamed"
      this.loads[id] = (this.loads[id] || 0) + 1
      const n = this.loads[id]

      // The first load of a frame is that frame opening. Any load after it is a document
      // being replaced under us, which on a provider with no resume is the film starting
      // again -- the finding, not the furniture.
      this.record(n === 1 ? "frame-load" : "frame-reload", { frame: id, n: n })
      if (n > 1) this.say(`${id} reloaded`, true)
    }, true)
  }

  // The browser's own doings, each of which has been offered at some point as the reason a
  // film stopped, and none of which can be ruled out after the fact without a record.
  watchTheBrowser() {
    this.on(document, "visibilitychange", () => this.record("visibility", { state: document.visibilityState }))
    // Chrome may freeze a background tab, which tears down media and is announced nowhere
    // else at all.
    this.on(document, "freeze", () => this.record("freeze"))
    this.on(document, "resume", () => this.record("resume"))
    this.on(document, "fullscreenchange", () => this.record("fullscreen", { on: Boolean(document.fullscreenElement) }))
    this.on(window, "pagehide", (event) => this.record("pagehide", { persisted: event.persisted }))
    this.on(window, "pageshow", (event) => this.record("pageshow", { persisted: event.persisted }))
    // This page answers a history traversal with a full reload (cinema-navigation's
    // historyMoved), so a stray back-swipe on a trackpad reloads the film. If it happens,
    // it happens here.
    this.on(window, "popstate", () => this.record("popstate", { history: history.length }))
    this.on(window, "online", () => this.record("online"))
    this.on(window, "offline", () => this.record("offline"))
    this.on(window, "error", (event) => this.record("error", { message: String(event.message).slice(0, 160) }))
    this.on(window, "unhandledrejection", (event) => this.record("rejection", { reason: String(event.reason).slice(0, 160) }))
  }

  // What the page itself is doing behind the film: warming a second player, giving up on
  // one, moving to another entry. cinema-navigation announces each so this can hear it
  // without reaching inside the controller.
  watchTheChannel() {
    this.on(document, "cinema-navigation:spare-built", ({ detail }) =>
      this.record("spare-built", { role: detail.role, adapter: detail.adapter }))
    this.on(document, "cinema-navigation:spare-spoke", ({ detail }) =>
      this.record("spare-spoke", { role: detail.role }))
    // The answer to the question this whole readout was built for: did the warmed player
    // stop when it was told to, and if not, was its frame taken away.
    this.on(document, "cinema-navigation:spare-verdict", ({ detail }) => {
      this.record(detail.kept ? "spare-stopped" : "spare-kept-playing",
                  { role: detail.role, verdict: detail.verdict })
      this.say(detail.kept ? "stopped" : `DROPPED — ${detail.verdict}`, !detail.kept)
    })
    this.on(document, "cinema-navigation:leaving", () => this.record("leaving"))
    this.on(document, "cinema-navigation:moved", () => this.record("moved", { url: location.pathname }))
    this.on(document, "player-progress:up-next", () => this.record("up-next"))
    this.on(document, "auto-advance:move", () => this.record("auto-advance"))
  }

  // cinema-navigation's `worthWarming`, asked here so the readout can say up front whether
  // this page is even capable of the fault being looked for.
  wouldWarm() {
    if (this.element.dataset.preload !== "true") return false
    if (navigator.connection?.saveData) return false
    if ((navigator.deviceMemory ?? 8) < 4) return false

    return window.innerWidth >= 900
  }

  // ---- recording ----------------------------------------------------------------------

  record(event, detail) {
    const at = (performance.now() - this.started) / 1000
    const line = { run: this.run, at: Number(at.toFixed(1)), clock: new Date().toISOString(), event, ...detail }

    this.log.push(line)
    this.store(line)
    this.draw(line)
    // Printed as well, for the case where nothing on the page is a VidSrc frame and the
    // console is usable after all. Flattened into the message, because a console renders
    // an object as the word "Object" until it is clicked and a copied log then says
    // nothing at all.
    console.log(`[playback ${this.clock(line.at)}] ${event} ${this.summarise(detail)}`.trimEnd())
  }

  summarise(detail) {
    return detail ? Object.entries(detail).map(([key, value]) => `${key}=${value}`).join(" ") : ""
  }

  clock(s) {
    return `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`
  }

  // Kept across reloads, because the event most worth recording is the one that ends the
  // page recording it. Everything here is wrapped: storage can be full, or refused
  // outright in a private window, and a readout that throws is worse than one that forgets.
  store(line) {
    try {
      const kept = this.stored().concat(line).slice(-KEPT_LINES)
      localStorage.setItem(STORE, JSON.stringify(kept))
    } catch {
      // Out of room or not allowed. The run in memory is still complete.
    }
  }

  stored() {
    try {
      const kept = JSON.parse(localStorage.getItem(STORE) || "[]")
      return Array.isArray(kept) ? kept : []
    } catch {
      return []
    }
  }

  // ---- the readout ---------------------------------------------------------------------

  drawStored() {
    const previous = this.stored()
    if (!previous.length) return

    previous.forEach((line) => this.draw(line, true))
    this.draw({ at: 0, event: `— above: ${previous.length} lines from earlier runs —` }, true)
  }

  // Built rather than written as markup. Some of what is recorded is a URL or an error
  // message from elsewhere, and a readout that renders those is one they can write to.
  draw(line, old = false) {
    if (!this.hasLogTarget) return

    const at = document.createElement("span")
    at.className = "playback-debug__at"
    at.textContent = this.clock(line.at)

    const name = document.createElement("span")
    if (LOUD.includes(line.event)) name.className = "playback-debug__loud"
    name.textContent = line.event

    const rest = { ...line }
    delete rest.at; delete rest.clock; delete rest.event; delete rest.run

    const row = document.createElement("div")
    row.className = old ? "playback-debug__line playback-debug__line--old" : "playback-debug__line"
    row.append(at, " ", name)
    if (Object.keys(rest).length) row.append(` ${this.summarise(rest)}`)

    this.logTarget.append(row)
    this.logTarget.scrollTop = this.logTarget.scrollHeight
  }

  // How many players are on the page, refreshed every second. This is the number the page
  // exists to show: one is the film, two for more than a moment is a second one playing
  // behind it.
  paintCounts() {
    const frames = document.querySelectorAll("#cinema-frames iframe").length
    if (this.hasFramesTarget) this.framesTarget.textContent = String(frames)
    if (this.hasElapsedTarget) this.elapsedTarget.textContent = this.clock((performance.now() - this.started) / 1000)
    if (this.hasHistoryTarget) this.historyTarget.textContent = `${history.length}${history.length >= 50 ? " (capped)" : ""}`
    const heap = this.heap()
    if (this.hasHeapTarget) this.heapTarget.textContent = heap === null ? "—" : `${heap} MB`

  }

  // What the bar says about the last thing worth knowing, and whether to stop being
  // background about it. Sticky: an alarm raised at minute three is still the reason the
  // film died at minute forty, and clearing it after a few seconds would lose that.
  say(what, alarm = false) {
    if (this.hasVerdictTarget) this.verdictTarget.textContent = what
    if (alarm) this.element.dataset.alarm = "true"
  }

  heap() {
    return performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) : null
  }

  tick() {
    this.record("tick", {
      frames: document.querySelectorAll("#cinema-frames iframe").length,
      history: history.length,
      heapMb: this.heap(),
    })
  }

  // ---- the controls ---------------------------------------------------------------------

  toggle() {
    this.element.dataset.open = this.element.dataset.open === "true" ? "false" : "true"
  }

  // The one thing none of this can observe is the picture. This is how the moment it
  // actually jumped gets into the record beside everything else.
  mark() {
    this.record("MARK — saw it happen")
  }

  copy() {
    const text = JSON.stringify(this.stored(), null, 2)
    navigator.clipboard?.writeText(text).then(
      () => this.record("log copied"),
      () => console.log(text)
    )
  }

  // A run worth keeping is copied out first; this is for starting a clean one.
  clear() {
    try {
      localStorage.removeItem(STORE)
    } catch {
      // Nothing to clear, or not allowed to. The readout below is emptied either way.
    }
    if (this.hasLogTarget) this.logTarget.replaceChildren()
    this.record("log cleared")
  }

  // Listeners are on the document and the window rather than on this element, so they have
  // to be taken off by hand. Kept in one list so that disconnect cannot miss one.
  on(target, event, handler, capture = false) {
    this.listeners.push([target, event, handler, capture])
    target.addEventListener(event, handler, capture)
  }
}
