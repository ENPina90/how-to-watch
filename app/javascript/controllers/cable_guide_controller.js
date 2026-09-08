import { Controller } from "@hotwired/stimulus"

// The TV guide: the whole dial across a few hours, over the channel you are watching.
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
// The grid is fetched when the guide is first opened. It is only ever wanted deliberately,
// it is identical for everybody, and one built into the page would sit there going stale
// while a two-hour film played.
const STALE_AFTER = 5 * 60 * 1000

// Keys the guide takes over while it is up. The arrows are the point: player-keys seeks
// with left and right, and a viewer moving around a grid does not expect the film
// underneath to jump five seconds every time.
const CLAIMED_KEYS = ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Escape", "Enter"]

export default class extends Controller {
  static targets = ["panel", "body", "clock", "detailChannel", "detailTitle", "detailMeta", "detailPlot"]
  static classes = ["open"]
  static values = { url: String, channel: String, zone: String }

  connect() {
    this.keyed = (event) => this.handleKey(event)
    // Capture, so a key the guide has claimed is taken before player-keys sees it on the
    // document. Bubbling would let the film seek first and the guide react afterwards.
    document.addEventListener("keydown", this.keyed, true)
  }

  disconnect() {
    document.removeEventListener("keydown", this.keyed, true)
    document.body.classList.remove("cable-guide-open")
    this.stopClock()
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
    // The sidebar and its toggle sit outside the cinema screen, so no rule inside it can
    // reach them -- and both would otherwise sit on top of a guide that has taken the
    // screen over. This is what the stylesheet hides them by.
    document.body.classList.add("cable-guide-open")

    if (this.stale) await this.load()
    this.startClock()
  }

  close() {
    this.panelTarget.hidden = true
    this.element.classList.remove(...this.openClasses)
    document.body.classList.remove("cable-guide-open")
    this.stopClock()
  }

  get stale() {
    return !this.loadedAt || Date.now() - this.loadedAt > STALE_AFTER
  }

  // The window the grid covers is decided by the server from the clock, so a guide opened
  // an hour later is a different four hours and has to be asked for again.
  async load() {
    try {
      const response = await fetch(`${this.urlValue}?channel=${encodeURIComponent(this.channelValue)}`,
                                   { headers: { Accept: "text/html" } })
      if (!response.ok) return this.failed()

      this.bodyTarget.innerHTML = await response.text()
      this.loadedAt = Date.now()
      this.describe(this.bodyTarget.querySelector(".tvguide__programme--live"))
      this.scrollToTuned()
    } catch {
      this.failed()
    }
  }

  failed() {
    // A listing that will not load costs nothing that matters -- the channel is still
    // playing behind it, which is what the viewer came for.
    this.bodyTarget.innerHTML = '<p class="tvguide__loading">Listings unavailable.</p>'
    this.loadedAt = null
  }

  // The row you are on, brought into view. A dial of six fits; a longer one will not.
  scrollToTuned() {
    this.bodyTarget.querySelector(".tvguide__row--tuned")
      ?.scrollIntoView({ block: "nearest" })
  }

  // Hovering or focusing a programme fills the panel beside the picture. Mouseover rather
  // than mouseenter so one listener on the grid serves every cell in it.
  preview(event) {
    this.describe(event.target.closest(".tvguide__programme"))
  }

  describe(programme) {
    if (!programme) return

    const { guideChannel, guideNumber, guideTitle, guideTimes, guideYear, guidePlot } = programme.dataset

    this.detailChannelTarget.textContent = guideChannel ?? ""
    this.detailTitleTarget.textContent = guideTitle ? `“${guideTitle}”` : ""
    this.detailMetaTarget.textContent =
      [guideTimes, guideYear, guideNumber && `Ch ${guideNumber} - ${guideChannel}`]
        .filter(Boolean).join("  ·  ")
    this.detailPlotTarget.textContent = guidePlot ?? ""
  }

  // Tuning happens through cinema-navigation, which is on the same element: the cells carry
  // data-cinema-move, so its own click handler answers them and the channel changes in
  // place with the guide still up. All this does is move the highlight to follow.
  tuned(event) {
    const programme = event.target.closest("[data-cable-guide-tune]")
    if (!programme) return

    const row = programme.closest(".tvguide__row")
    this.bodyTarget.querySelectorAll(".tvguide__row--tuned")
      .forEach((tuned) => tuned.classList.remove("tvguide__row--tuned"))
    row?.classList.add("tvguide__row--tuned")

    // The screen element survives a move, so the channel it names would otherwise still be
    // the one the page was first rendered for -- and the next refetch would light the wrong
    // row. Nothing else reads it, but a value that lies is worth not keeping.
    this.channelValue = programme.dataset.cableGuideTune
  }

  handleKey(event) {
    if (!this.open || !CLAIMED_KEYS.includes(event.key)) return
    // Typing somewhere is typing somewhere, even with the guide up.
    if (event.target.matches("input, textarea, select")) return

    event.preventDefault()
    event.stopPropagation()

    if (event.key === "Escape") return this.close()
    if (event.key === "Enter") return this.focused?.click()

    this.move(event.key)
  }

  // Up and down change channel, left and right step along a row -- which is how a cable
  // guide has always worked, and it is the reason the arrows are taken off the player.
  move(key) {
    const rows = [...this.bodyTarget.querySelectorAll(".tvguide__row")]
    if (rows.length === 0) return

    const current = this.focused
    const row = current?.closest(".tvguide__row")
    const rowAt = row ? rows.indexOf(row) : -1

    let next
    if (key === "ArrowUp" || key === "ArrowDown") {
      const step = key === "ArrowDown" ? 1 : -1
      const target = rows[(rowAt + step + rows.length) % rows.length]
      // Landing on the programme nearest where you were, rather than the row's first --
      // moving down a column should stay in roughly the same column.
      next = this.nearest(target, current)
    } else {
      const cells = [...(row ?? rows[0]).querySelectorAll(".tvguide__programme")]
      const at = current ? cells.indexOf(current) : -1
      next = cells[Math.min(Math.max(at + (key === "ArrowRight" ? 1 : -1), 0), cells.length - 1)]
    }

    if (!next) return
    this.focused = next
    next.focus({ preventScroll: false })
    this.describe(next)
  }

  // The cell in a row whose span covers where the current one starts.
  nearest(row, current) {
    const cells = [...row.querySelectorAll(".tvguide__programme")]
    if (cells.length === 0 || !current) return cells[0]

    const want = parseFloat(current.style.left) || 0
    return cells.find((cell) => {
      const left = parseFloat(cell.style.left) || 0
      return left + (parseFloat(cell.style.width) || 0) > want
    }) ?? cells[cells.length - 1]
  }

  // The corner clock, which is the only thing on the grid that says what time it is now.
  startClock() {
    this.tick()
    this.clockTimer = setInterval(() => this.tick(), 1000)
  }

  stopClock() {
    clearInterval(this.clockTimer)
  }

  // In the schedule's zone, not the viewer's. Every time on the grid is a cable time, so a
  // clock running locally would disagree with the column beside it for anybody watching
  // from somewhere else -- and the whole grid is built on the two agreeing.
  tick() {
    if (!this.hasClockTarget) return

    const options = { hour: "numeric", minute: "2-digit", second: "2-digit", hour12: true }
    if (this.zoneValue) options.timeZone = this.zoneValue

    this.clockTarget.textContent = new Intl.DateTimeFormat("en-US", options)
      .format(new Date()).replace(/\s?[AP]M$/i, "")
  }
}
