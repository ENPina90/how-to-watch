import { Controller } from "@hotwired/stimulus"

// The TV guide: the whole dial across a day, over the channel you are watching.
//
// It sits on the cinema screen rather than in the chrome, because tuning a channel from it
// should not close it -- cinema-navigation replaces the chrome on every move, and a listing
// that vanished the moment you used it would be no listing at all. What changes when you
// tune is the picture in the corner and which row is lit, and both are handled here.
//
// The picture is not moved into the corner. Moving an iframe in the DOM reloads it, which
// would stop the film to show you a grid about the film; the stylesheet resizes the frame
// stack into the corner instead and the player never knows.
//
// Everything time-shaped is worked out here rather than baked into the markup. The grid is
// fetched once and then sits there for as long as somebody reads it, and in that time the
// programme it says is on will end and the next one will start. So the line marking now
// moves, the cell it marks moves with it, and the panel follows -- all off the clock, none
// of it off the render.
const STALE_AFTER = 5 * 60 * 1000

// How often the clock is consulted. A cell boundary is a whole minute wide at any sane
// zoom, so this is about the line moving smoothly rather than about catching the change.
const TICK = 5000

// The panel follows the pointer, and goes back to what is actually playing when the
// pointer stops. Long enough to read a synopsis without it snatching the text away.
const REVERT_AFTER = 8000

// Left alone this long, the guide scrolls itself back to now. Somebody who wandered off
// down tomorrow afternoon and came back should not have to find their way home.
const RECENTER_AFTER = 5 * 60 * 1000

// Where the line sits after a recentre: a third in, so there is a little of the past on
// screen and most of the width is what has not happened yet.
const NOW_AT = 1 / 3

// Keys the guide takes over while it is up, so that reading the grid does not also scroll
// the page under it. The film is not at risk from them -- a cable channel has no transport
// at all, see player-keys' `transport` value -- but the browser's own use of them still has
// to be taken away while the grid has them.
//
// Up and down are deliberately absent. On a cable box those change the channel whether the
// guide is up or not, so they are left to cinema-navigation: the dial turns, the picture in
// the corner changes, and the guide's highlight follows it. Reading a listing and changing
// channel are the same gesture, which is most of what a guide is for.
const CLAIMED_KEYS = ["ArrowLeft", "ArrowRight", "Escape", "Enter"]

export default class extends Controller {
  static targets = [
    "panel", "body", "grid", "clock", "nowLine",
    "detailChannel", "detailTitle", "detailMeta", "detailPlot", "detailWatched"
  ]
  static classes = ["open"]
  static values = { url: String, channel: String }

  connect() {
    this.keyed = (event) => this.handleKey(event)
    // Capture, so a key the guide has claimed is taken before player-keys sees it on the
    // document. Bubbling would let the film seek first and the guide react afterwards.
    document.addEventListener("keydown", this.keyed, true)
  }

  disconnect() {
    document.removeEventListener("keydown", this.keyed, true)
    this.stopTicking()
    this.clearIdleTimers()
  }

  toggle() {
    this.open ? this.close() : this.show()
  }

  get open() {
    return !this.panelTarget.hidden
  }

  async show() {
    this.panelTarget.hidden = false
    this.element.classList.add(...this.openClasses)

    if (this.stale) await this.load()

    this.startTicking()
    this.recentre({ smooth: false })
    this.rest()
  }

  close() {
    this.panelTarget.hidden = true
    this.element.classList.remove(...this.openClasses)
    this.stopTicking()
    this.clearIdleTimers()
  }

  get stale() {
    return !this.loadedAt || Date.now() - this.loadedAt > STALE_AFTER
  }

  // The window the grid covers is worked out by the server from the clock and from the
  // zone the viewer is in, so a guide opened an hour later is a different day and has to be
  // asked for again.
  async load() {
    const query = new URLSearchParams({ channel: this.channelValue, tz: this.timeZone })

    try {
      const response = await fetch(`${this.urlValue}?${query}`, { headers: { Accept: "text/html" } })
      if (!response.ok) return this.failed()

      this.bodyTarget.innerHTML = await response.text()
      this.loadedAt = Date.now()
    } catch {
      this.failed()
    }
  }

  // Whatever the browser believes it is in. The server takes it as a hint and falls back to
  // the schedule's own zone if it does not recognise it.
  get timeZone() {
    try {
      return Intl.DateTimeFormat().resolvedOptions().timeZone ?? ""
    } catch {
      return ""
    }
  }

  failed() {
    // A listing that will not load costs nothing that matters -- the channel is still
    // playing behind it, which is what the viewer came for.
    this.bodyTarget.innerHTML = '<p class="tvguide__loading">Listings unavailable.</p>'
    this.loadedAt = null
  }

  // ---- the clock ------------------------------------------------------------------

  startTicking() {
    this.tick()
    this.ticker = setInterval(() => this.tick(), TICK)
  }

  stopTicking() {
    clearInterval(this.ticker)
  }

  // Everything that depends on what time it is, in one place and on one schedule: the
  // corner clock, the line across the grid, and which cell that line is inside.
  tick() {
    const now = new Date()
    this.showClock(now)
    this.placeNowLine(now)
    this.markLive(now)
    // Only when nothing is being pointed at -- otherwise the programme that just started
    // would yank the panel out from under somebody reading about a different one.
    if (!this.previewing) this.describeCurrent()
  }

  showClock(now) {
    if (!this.hasClockTarget) return

    this.clockTarget.textContent = new Intl.DateTimeFormat("en-US", {
      hour: "numeric", minute: "2-digit", second: "2-digit", hour12: true
    }).format(now).replace(/\s?[AP]M$/i, "")
  }

  // In hours from the left edge of the track, which is the unit everything on the grid is
  // placed in -- so the line lands on the same scale as the cells whatever the zoom.
  placeNowLine(now) {
    if (!this.hasNowLineTarget || !this.hasGridTarget) return

    const hours = (now.getTime() - this.windowStart) / 3600000
    const outside = hours < 0 || hours > this.windowHours

    this.nowLineTarget.hidden = outside
    if (!outside) this.nowLineTarget.style.setProperty("--guide-now-hours", hours.toFixed(5))
  }

  get windowStart() {
    return Number(this.gridTarget?.dataset.windowStart ?? 0)
  }

  get windowHours() {
    return Number(this.gridTarget?.dataset.windowHours ?? 0)
  }

  // The cell the line is inside, on the channel being watched. It moves twice: when the
  // clock crosses into the next programme, and when the viewer tunes somewhere else.
  markLive(now = new Date()) {
    if (!this.hasBodyTarget) return

    const was = this.bodyTarget.querySelector(".tvguide__programme--live")
    const is = this.currentCell(now)
    if (was === is) return

    was?.classList.remove("tvguide__programme--live")
    is?.classList.add("tvguide__programme--live")
  }

  currentCell(now = new Date()) {
    const row = this.bodyTarget?.querySelector(".tvguide__row--tuned")
    if (!row) return null

    const at = now.getTime()
    return [...row.querySelectorAll(".tvguide__programme")].find((cell) => {
      return Number(cell.dataset.guideStart) <= at && Number(cell.dataset.guideEnd) > at
    }) ?? null
  }

  // ---- the panel ------------------------------------------------------------------

  // Hovering or focusing a programme fills the panel beside the picture. Mouseover rather
  // than mouseenter so one listener on the grid serves every cell in it.
  preview(event) {
    const programme = event.target.closest(".tvguide__programme")
    if (!programme) return

    this.previewing = true
    this.describe(programme)
    this.rest()
  }

  // The pointer has left the grid entirely.
  released() {
    this.previewing = false
    this.describeCurrent()
  }

  // Back to what is actually on. The panel is a caption for the picture beside it, and the
  // picture is what is playing -- so that is where it settles when nobody is pointing.
  describeCurrent() {
    this.previewing = false
    this.describe(this.currentCell())
  }

  describe(programme) {
    if (!programme) return

    const data = programme.dataset

    this.detailChannelTarget.textContent = data.guideChannel ?? ""
    this.detailChannelTarget.href = data.guideChannelUrl ?? "#"
    this.detailTitleTarget.textContent = data.guideTitle ? `“${data.guideTitle}”` : ""
    this.detailTitleTarget.href = data.guideWatchUrl ?? "#"
    this.detailMetaTarget.textContent = [
      this.span(data), data.guideYear, data.guideNumber && `Ch ${data.guideNumber} - ${data.guideChannel}`
    ].filter(Boolean).join("  ·  ")
    this.detailPlotTarget.textContent = data.guidePlot ?? ""
    this.detailWatchedTarget.hidden = data.guideWatched !== "true"
  }

  // The programme's own hours, in the viewer's zone -- the same reading the grid's columns
  // are labelled with, because both are formatted from the same instants by the browser.
  span({ guideStart, guideEnd }) {
    if (!guideStart || !guideEnd) return null

    const clock = new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" })
    return `${clock.format(new Date(Number(guideStart)))} - ${clock.format(new Date(Number(guideEnd)))}`
  }

  // ---- tuning ---------------------------------------------------------------------

  // Tuning happens through cinema-navigation, which is on the same element: the cells carry
  // data-cinema-move, so its own click handler answers them and the channel changes in
  // place with the guide still up. All this does is move the highlight to follow.
  tuned(event) {
    const programme = event.target.closest("[data-cable-guide-tune]")
    if (!programme) return

    this.lightUp(programme.dataset.cableGuideTune)
  }

  // The row that is lit, brought into view. A dial of six fits on screen; a longer one
  // would leave the channel you just turned to somewhere below the fold.
  scrollToTuned() {
    this.bodyTarget.querySelector(".tvguide__row--tuned")?.scrollIntoView({ block: "nearest" })
  }

  // The channel changed by something other than a click on the grid -- the arrows, the
  // remote, the clock running out. The guide sits outside the chrome so that using it does
  // not close it, which also means a move replaces nothing in here: without being told, it
  // goes on lighting the channel it was opened from long after the picture has moved.
  channelChanged() {
    this.lightUp(document.getElementById("cinema-chrome")?.dataset.cableChannelId)
  }

  // Move the highlight, and everything that hangs off it.
  lightUp(channelId) {
    if (!channelId || !this.hasBodyTarget) return

    // The screen element survives a move, so the channel it names would otherwise still be
    // the one the page was first rendered for -- and the next refetch would light the wrong
    // row.
    this.channelValue = channelId

    this.bodyTarget.querySelectorAll(".tvguide__row--tuned")
      .forEach((tuned) => tuned.classList.remove("tvguide__row--tuned"))
    this.bodyTarget
      .querySelector(`.tvguide__row[data-channel-id="${CSS.escape(channelId)}"]`)
      ?.classList.add("tvguide__row--tuned")

    // What is live has moved to another row, and the picture has moved to match.
    this.markLive()
    this.describeCurrent()
    this.scrollToTuned()
  }

  // ---- being left alone -----------------------------------------------------------

  // Any sign of life. Two things are waiting on it: the panel, which goes back to what is
  // playing shortly after the pointer stops, and the grid, which finds its way back to now
  // after rather longer.
  rest() {
    this.clearIdleTimers()
    this.revertTimer = setTimeout(() => this.describeCurrent(), REVERT_AFTER)
    this.recentreTimer = setTimeout(() => {
      this.recentre({ smooth: true })
      this.describeCurrent()
      this.rest()
    }, RECENTER_AFTER)
  }

  clearIdleTimers() {
    clearTimeout(this.revertTimer)
    clearTimeout(this.recentreTimer)
  }

  // Put the line marking now a third of the way across, so there is a little of what has
  // been and plenty of what is coming.
  recentre({ smooth }) {
    if (!this.hasBodyTarget || !this.hasNowLineTarget || this.nowLineTarget.hidden) return

    const line = this.nowLineTarget.offsetLeft
    const left = Math.max(line - this.bodyTarget.clientWidth * NOW_AT, 0)

    this.bodyTarget.scrollTo({ left: left, behavior: smooth ? "smooth" : "auto" })
  }

  // ---- the keyboard ---------------------------------------------------------------

  handleKey(event) {
    if (!this.open || !CLAIMED_KEYS.includes(event.key)) return
    // Typing somewhere is typing somewhere, even with the guide up.
    if (event.target instanceof Element && event.target.matches("input, textarea, select")) return

    event.preventDefault()
    event.stopPropagation()

    if (event.key === "Escape") return this.close()
    if (event.key === "Enter") return this.focused?.click()

    this.step(event.key)
    this.rest()
  }

  // Left and right walk along the row that is lit, to read what is on later. Up and down
  // are not here: they turn the dial, and the highlight follows of its own accord.
  step(key) {
    const row = this.focused?.closest(".tvguide__row") ??
                this.bodyTarget.querySelector(".tvguide__row--tuned") ??
                this.bodyTarget.querySelector(".tvguide__row")
    if (!row) return

    const cells = [...row.querySelectorAll(".tvguide__programme")]
    if (cells.length === 0) return

    // Entering a row from nowhere starts at what is on, rather than at the far end of the
    // day -- the same place the eye starts.
    const from = this.focused && cells.includes(this.focused)
      ? cells.indexOf(this.focused)
      : cells.indexOf(this.currentCell())
    const next = cells[Math.min(Math.max(from + (key === "ArrowRight" ? 1 : -1), 0), cells.length - 1)]
    if (!next) return

    this.focused = next
    this.previewing = true
    next.focus({ preventScroll: false })
    this.describe(next)
  }
}
