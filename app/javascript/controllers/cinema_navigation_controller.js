import { Controller } from "@hotwired/stimulus"
import { playerAdapterFor, isControllable } from "services/player_adapter"

// How long to leave the film alone before warming the next one. The preload is a second
// video stream on the same connection, and the first seconds of the one being watched are
// the ones that must not stutter.
const PRELOAD_DELAY = 5000

// Moving between entries without rebuilding the page.
//
// The five ways out of an entry -- the channel above and below, the entry either side, and
// the shuffle -- used to be ordinary navigations, which meant the player was torn down and
// built again from nothing every time. That is the ~1.5s an embed takes to reach a moving
// picture (docs/guides/VIDSRC.md §6a), paid on every move.
//
// So the move happens in place instead. The server still renders the whole page and still
// records the position, exactly as before -- the difference is only that the answer is
// fetched and pasted in rather than navigated to. The screen itself is untouched, which is
// what lets fullscreen survive a change of channel: fullscreen belongs to an element, and
// this leaves that element where it is.
//
// What does change is everything that names the entry being watched, and that reaches
// outside the player page: the frame, the chrome around it, the entries sidebar, and the
// Now Playing card, which the layout draws in the main sidebar from the same `@entry`.
// A move that misses any of them leaves the page describing the film before this one.
//
// Everything is delegated from the screen rather than bound to the controls, because the
// controls are inside the chrome and are replaced by every move.
//
// The channel below is warmed in advance, because that is the direction somebody surfing
// travels: its page is fetched and its player built in a second frame stacked behind the
// one being watched, then paused as soon as it will listen. Pressing down promotes that
// frame and pastes in the page already fetched, so the move costs nothing -- no request,
// no player to build, ~1.5s of embed load already spent. Every other direction still pays
// it, which is the honest trade for one extra stream rather than five.
//
// The warmed frame is stacked behind rather than hidden. A frame the browser believes
// nobody can see is a frame it feels free to stop buffering, which would leave it as cold
// as no preload at all.
//
// Anything unexpected falls back to a real navigation. A channel with nothing in it
// redirects to its own page, a session can lapse, a fetch can fail -- none of those
// produce a player page to paste in, and all of them are somebody's ordinary business
// rather than an error worth reporting.
export default class extends Controller {
  static classes = ["moving"]
  static values = { preload: Boolean }

  connect() {
    this.clicked = (event) => this.linkClicked(event)
    this.submitted = (event) => this.formSubmitted(event)
    this.wentBack = () => this.historyMoved()

    this.element.addEventListener("click", this.clicked)
    this.element.addEventListener("submit", this.submitted)
    window.addEventListener("popstate", this.wentBack)

    this.scheduleWarming()
  }

  disconnect() {
    this.element.removeEventListener("click", this.clicked)
    this.element.removeEventListener("submit", this.submitted)
    window.removeEventListener("popstate", this.wentBack)
    this.discardWarmed()
  }

  // Only the controls that say so. The channel name, the home button and anything else
  // that leaves the player behind are ordinary links and stay ordinary.
  linkClicked(event) {
    const link = event.target.closest("a[data-cinema-move]")
    if (!link || event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return

    event.preventDefault()

    // The one direction that may already be waiting.
    if (link.dataset.cinemaPreload !== undefined && this.warmed) return this.promote()

    this.moveTo(link.href)
  }

  // The three that record a position first are forms, not links, so they arrive here
  // instead. The form already carries its own `_method` and CSRF token; sending it whole
  // is what keeps this in step with whatever button_to generates.
  formSubmitted(event) {
    const form = event.target.closest("form[data-cinema-move]")
    if (!form) return

    event.preventDefault()
    this.moveTo(form.action, { method: "POST", body: new FormData(form) })
  }

  // The up-next card asking to advance. It offers rather than navigates, so that it still
  // works if this controller is not around to answer.
  moveFromEvent(event) {
    const { url, body } = event.detail
    event.preventDefault()
    this.moveTo(url, { method: "POST", body: body })
  }

  async moveTo(url, options = {}) {
    // A second press while the first is in flight would race two pages into the same DOM.
    if (this.moving) return
    this.moving = true
    this.element.classList.add(...this.movingClasses)

    // Where the player got to is worth keeping before the frame changes under it -- there
    // is no unload here to catch it later.
    this.dispatch("leaving", { target: document })

    try {
      const response = await fetch(url, { ...options, headers: { Accept: "text/html" }, redirect: "follow" })
      if (!response.ok) return this.giveUp(url)

      const page = new DOMParser().parseFromString(await response.text(), "text/html")
      // Not a player page: a channel with nothing to play, or a sign-in form.
      if (!page.getElementById("cinema-chrome")) return this.giveUp(response.url)

      this.apply(page, response.url)
    } catch {
      this.giveUp(url)
    } finally {
      this.moving = false
      this.element.classList.remove(...this.movingClasses)
    }
  }

  apply(page, url) {
    // The frame first. It is the slow part by an order of magnitude, and everything below
    // is instant, so it should not wait behind them.
    const frame = document.getElementById("cinema")
    const incoming = page.getElementById("cinema")
    if (frame && incoming && frame.src !== incoming.src) {
      // The title is what a screen reader calls the frame, so it has to move with the src
      // or the player is announced as whatever was playing before.
      frame.title = incoming.title
      frame.src = incoming.src
    }

    this.applyChrome(page)
    history.pushState({}, "", url)

    // Whatever was warm was warm for the channel below the entry we have just left.
    this.discardWarmed()
    this.scheduleWarming()
  }

  // Everything except the frame: promoting a warmed frame has already dealt with that.
  applyChrome(page) {
    this.swap("cinema-chrome", page)
    // Contents rather than the elements themselves. Both of these are panels whose open
    // or shut state is the viewer's, held on the element by scripts that ran once at page
    // load -- the entries sidebar is rendered shut every time and opened afterwards from
    // what was remembered, so handing it back the server's version closes it for good.
    this.swapInner("entriesSidebar", page)
    this.swapInner("nowPlayingContent", page)

    document.title = page.title
  }

  swap(id, page) {
    const current = document.getElementById(id)
    const incoming = page.getElementById(id)
    // Stimulus notices the replacement itself, so the controllers inside come back
    // connected to the new entry's values.
    if (current && incoming) current.replaceWith(incoming)
  }

  swapInner(id, page) {
    const current = document.getElementById(id)
    const incoming = page.getElementById(id)
    if (!current || !incoming) return

    // The data attributes describe the entry and have to move; class and style describe
    // whether the panel is open and must not, because only the page knows that by now.
    for (const { name, value } of incoming.attributes) {
      if (name.startsWith("data-")) current.setAttribute(name, value)
    }

    current.replaceChildren(...incoming.childNodes)
  }

  // ---- warming the channel below --------------------------------------------------

  // Not on a metered connection, not on a machine with little to spare, and not on a
  // phone: this is a second video stream, and the point of it is a nicety.
  get worthWarming() {
    if (!this.preloadValue) return false
    if (navigator.connection?.saveData) return false
    if ((navigator.deviceMemory ?? 8) < 4) return false

    return window.innerWidth >= 900
  }

  scheduleWarming() {
    if (!this.worthWarming) return

    this.warmingTimer = setTimeout(() => this.warm(), PRELOAD_DELAY)
  }

  async warm() {
    const link = this.element.querySelector("a[data-cinema-move][data-cinema-preload]")
    if (!link || this.warmed) return

    try {
      // Marked as speculative both ways: the header tells the server not to record a
      // position for a channel nobody has opened, and the XHR header keeps it out of the
      // visit count for the same reason.
      const response = await fetch(link.href, {
        headers: { Accept: "text/html", "X-Cinema-Preload": "1", "X-Requested-With": "XMLHttpRequest" }
      })
      if (!response.ok) return

      const page = new DOMParser().parseFromString(await response.text(), "text/html")
      const incoming = page.getElementById("cinema")
      // Nothing to warm: an empty channel, or the same entry we are already watching.
      if (!incoming || !incoming.src || incoming.src === document.getElementById("cinema")?.src) return

      this.warmed = { page: page, url: response.url }
      this.buildWarmedFrame(incoming)
    } catch {
      // A warm-up that fails costs the viewer nothing; the move it would have helped
      // simply pays full price.
    }
  }

  buildWarmedFrame(incoming) {
    const frame = document.createElement("iframe")
    frame.id = "cinema-next"
    frame.className = "cinema__frame"
    frame.title = incoming.title
    frame.setAttribute("referrerpolicy", "origin")
    // Autoplay, because a player that will not start is a player that buffers nothing --
    // and it is stopped a moment later, before it has anything to show.
    frame.setAttribute("allow", "autoplay")
    frame.src = incoming.src
    document.getElementById("cinema-frames").appendChild(frame)

    // Stop it as soon as it will listen. Commands before the player's first report are
    // dropped, so this waits for one -- which arrives well before the picture does.
    const adapter = this.adapterFor(incoming)
    if (!adapter) return

    this.warmedPlayer = playerAdapterFor(adapter, frame, {
      onState: () => {
        if (this.warmedPaused) return
        this.warmedPaused = true
        this.warmedPlayer.pause()
      }
    })
  }

  adapterFor(incoming) {
    const chrome = incoming.ownerDocument.getElementById("cinema-chrome")
    const name = chrome?.dataset.playerProgressAdapterValue
    return isControllable(name) ? name : null
  }

  // The move the warming was for: no request, no player to build.
  promote() {
    const { page, url } = this.warmed
    const live = document.getElementById("cinema")
    const next = document.getElementById("cinema-next")
    if (!live || !next) return this.moveTo(url)

    this.dispatch("leaving", { target: document })

    live.remove()
    next.id = "cinema"
    next.classList.add("cinema__frame--live")
    // It was stopped while it warmed; this is what it was warmed for.
    //
    // Unmuted as well as played. Nobody had touched the page when the warmed frame
    // started, so the browser started it muted -- which is what kept it quiet behind the
    // film being watched, and would otherwise leave the viewer landing on a silent
    // channel. Somebody has touched the page now: they pressed down.
    this.warmedPlayer?.unmute()
    this.warmedPlayer?.play()
    this.warmedPlayer?.destroy()
    this.warmedPlayer = null
    this.warmedPaused = false
    this.warmed = null

    this.applyChrome(page)
    history.pushState({}, "", url)

    // And line up whatever is below the channel we just landed on.
    this.scheduleWarming()
  }

  discardWarmed() {
    clearTimeout(this.warmingTimer)
    this.warmedPlayer?.destroy()
    this.warmedPlayer = null
    this.warmedPaused = false
    this.warmed = null
    document.getElementById("cinema-next")?.remove()
  }

  // The address bar was moved without a page load, so there is nothing in the document for
  // it to match. Letting the browser load it properly is both simplest and right.
  historyMoved() {
    window.leavingOnPurpose = true
    window.location.reload()
  }

  giveUp(url) {
    // The page asks "did you mean to leave?" whenever the frame has focus; this is the
    // page leaving deliberately.
    window.leavingOnPurpose = true
    window.location.assign(url)
  }
}
