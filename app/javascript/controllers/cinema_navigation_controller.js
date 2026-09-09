import { Controller } from "@hotwired/stimulus"
import { playerAdapterFor, isControllable } from "services/player_adapter"

// How long to leave the film alone before warming the next one. The preload is a second
// video stream on the same connection, and the first seconds of the one being watched are
// the ones that must not stutter.
const PRELOAD_DELAY = 5000

// The two spares, and they are for different things. `below` is the channel one step down
// the dial, warmed shortly after landing because that is where somebody surfing goes.
// `next` is what follows on this channel, warmed only once the current programme is nearly
// over. Each owns a frame of its own, so both can be waiting at the same time.
const BELOW = "below"
const NEXT = "next"
const FRAMES = { [BELOW]: "cinema-next", [NEXT]: "cinema-after" }

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
    this.keyed = (event) => this.keyPressed(event)

    this.spares = {}

    this.element.addEventListener("click", this.clicked)
    this.element.addEventListener("submit", this.submitted)
    window.addEventListener("popstate", this.wentBack)
    // On the document, not on this element: a keystroke goes to whatever has focus, which
    // after a page load is the body and is never inside the frame the film is in.
    document.addEventListener("keydown", this.keyed)

    this.scheduleWarming()
  }

  disconnect() {
    this.element.removeEventListener("click", this.clicked)
    this.element.removeEventListener("submit", this.submitted)
    window.removeEventListener("popstate", this.wentBack)
    document.removeEventListener("keydown", this.keyed)
    this.discardSpares()
  }

  // Up and down the dial from the keyboard, which is how anybody who has held a remote
  // expects to change channel.
  //
  // It presses the arrow rather than moving on its own. Everything the click path already
  // knows -- that down may have a channel warmed and waiting, that a second move must not
  // race the first, what to do when the answer is not a player page -- would otherwise have
  // to be repeated here and kept in step with itself.
  keyPressed(event) {
    if (event.key !== "ArrowUp" && event.key !== "ArrowDown") return
    if (event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return
    if (this.busyElsewhere(event)) return

    const arrow = this.element.querySelector(
      `a[data-cinema-channel="${event.key === "ArrowUp" ? "up" : "down"}"]`
    )
    // Signed out, or a page with nowhere to go. Leave the keystroke to the browser.
    if (!arrow) return

    event.preventDefault()
    arrow.click()
  }

  // Somewhere the arrows already mean something: a field being typed into, a select being
  // stepped through, or an open dialog -- the review prompt, the up-next card, the guide,
  // any of which is a question being asked that the channel behind it should not answer.
  busyElsewhere({ target }) {
    if (target instanceof HTMLElement && target.isContentEditable) return true
    if (target instanceof HTMLElement && /^(input|textarea|select)$/i.test(target.tagName)) return true

    return Boolean(document.querySelector(".modal.show"))
  }

  // Only the controls that say so. The channel name, the home button and anything else
  // that leaves the player behind are ordinary links and stay ordinary.
  linkClicked(event) {
    const link = event.target.closest("a[data-cinema-move]")
    if (!link || event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return

    event.preventDefault()

    // The one direction that may already be waiting -- but only when it is still what is
    // warm. Late in a programme the spare is re-aimed at whatever comes next on this
    // channel, and promoting that for a press of "down" would land on the wrong thing.
    if (this.spares[BELOW]?.request === link.href) return this.promote(BELOW)

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

  // Something on the page asking to advance -- the up-next card on the watch page, the
  // schedule running out on a cable channel. Both offer rather than navigate, so that they
  // still work if this controller is not around to answer.
  //
  // With a body it is the card, whose move records a position and so is a POST carrying its
  // own CSRF token. Without one it is a plain read of somewhere else, and posting to it
  // would not route.
  moveFromEvent(event) {
    const { url, body } = event.detail
    event.preventDefault()
    this.moveTo(url, body ? { method: "POST", body: body } : {})
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
      // Already warm and playing? Then the move costs nothing at all -- no request left to
      // make and no embed left to build. Matched on the address rather than on which
      // control was pressed, so it works however the move was started: the up-next card
      // posts a position first and lands here with the answer, and its answer is the same
      // page that was warmed.
      if (this.adoptSpare(incoming)) {
        // Said before the chrome goes in, so the controller inside it connects already
        // knowing: this player has been running with nobody in front of it, and wherever it
        // has reached is not somewhere anybody watched it reach.
        page.getElementById("cinema-chrome")?.setAttribute("data-player-progress-warmed-value", "true")
      } else {
        // The title is what a screen reader calls the frame, so it has to move with the src
        // or the player is announced as whatever was playing before.
        frame.title = incoming.title
        frame.src = incoming.src
      }
    }

    this.applyChrome(page)
    history.pushState({}, "", url)

    // Whatever is still warm was warmed for where we were, not for where we have arrived.
    this.discardSpares()
    this.scheduleWarming()
  }

  // Swap a spare in for the live frame, when one of them is already showing what we are
  // moving to. Which of the two it is does not matter here -- what matters is that the
  // address matches, so this works however the move was started: the up-next card posts a
  // position first and lands on the answer, with no link to hang a promotion off.
  //
  // Returns false when neither spare holds it, and the caller loads the src the ordinary
  // way.
  adoptSpare(incoming) {
    const live = document.getElementById("cinema")
    if (!live || !incoming?.src) return false

    const role = Object.keys(this.spares)
      .find((key) => document.getElementById(FRAMES[key])?.src === incoming.src)
    if (!role) return false

    const spare = this.spares[role]
    const frame = document.getElementById(FRAMES[role])

    live.remove()
    frame.id = "cinema"
    frame.classList.add("cinema__frame--live")

    // It was stopped and silenced while it warmed; this is what it was warmed for.
    //
    // Unmuted as well as played. Nobody had touched the page when the spare started, so the
    // browser started it muted -- which is what kept it quiet behind the film being watched,
    // and would otherwise leave the viewer landing on a silent channel. By now somebody has
    // touched the page, or a countdown they watched has run out.
    spare.player?.unmute()
    spare.player?.play()
    spare.player?.destroy()

    // Taken out of the store before the rest are discarded, or the frame just adopted would
    // be torn down again a moment later.
    delete this.spares[role]

    return true
  }

  // ---- the two spare frames --------------------------------------------------------

  // Not on a metered connection, not on a machine with little to spare, and not on a
  // phone: these are extra video streams, and the point of them is a nicety.
  get worthWarming() {
    if (!this.preloadValue) return false
    if (navigator.connection?.saveData) return false
    if ((navigator.deviceMemory ?? 8) < 4) return false

    return window.innerWidth >= 900
  }

  get channelBelow() {
    return this.element.querySelector("a[data-cinema-move][data-cinema-preload]")?.href
  }

  // What comes next on this channel, according to the page -- the entry the up-next card
  // will move to, the following episode of a series, or the cable channel at the moment it
  // changes. Absent where it cannot be known: an unordered channel advances by shuffling,
  // and there is no warming a coin toss.
  get nextOnChannel() {
    return document.getElementById("cinema-chrome")?.dataset.cinemaNextUrl
  }

  scheduleWarming() {
    if (!this.worthWarming) return

    this.warmingTimer = setTimeout(() => this.warm(BELOW, this.channelBelow), PRELOAD_DELAY)
  }

  // The second spare, warmed only once the current programme is nearly over.
  //
  // Late in a film the likelier move is forward rather than sideways, but the sideways one
  // does not stop being possible -- so this is a second spare rather than the first one
  // re-aimed, and for that last minute the page is running three video streams. That is the
  // trade: a third stream for as long as a set of closing credits, in exchange for the next
  // programme starting on the instant however the viewer gets there.
  warmNext() {
    this.warm(NEXT, this.nextOnChannel)
  }

  async warm(role, url) {
    if (!url || !this.worthWarming || this.spares[role]) return
    // The other spare may already be holding it -- the channel below can be showing the
    // same thing this channel is about to.
    if (Object.values(this.spares).some((spare) => spare.request === url)) return

    try {
      // Marked as speculative both ways: the header tells the server not to record a
      // position for a channel nobody has opened, and the XHR header keeps it out of the
      // visit count for the same reason.
      const response = await fetch(url, {
        headers: { Accept: "text/html", "X-Cinema-Preload": "1", "X-Requested-With": "XMLHttpRequest" }
      })
      if (!response.ok) return

      const page = new DOMParser().parseFromString(await response.text(), "text/html")
      const incoming = page.getElementById("cinema")
      // Nothing to warm: an empty channel, or what we are already watching. Compared with
      // the resume position taken out, because that is not what makes two embeds different
      // things -- asking for what is on next a little too early answers with the programme
      // already playing, a few seconds further in, and warming that would be a second
      // stream of the film we are already watching.
      if (!incoming?.src || this.samePlaying(incoming.src, document.getElementById("cinema")?.src)) return

      // Both the address asked for and the one it landed on: the first is how a control is
      // recognised as pointing at what is already warm, the second is what the history gets.
      // They differ whenever the server redirects, which "play this channel" always does.
      this.spares[role] = { request: url, page: page, url: response.url }

      // Only warm a player this page can drive. A frame it cannot pause is a frame playing
      // out loud behind the one being watched -- which is what a channel in its commercial
      // break is, since the adverts come from YouTube rather than from the film's provider.
      // The fetched page is kept either way: moving there then costs no request, only the
      // ~1.5s of embed load the warming would have spent.
      const adapter = this.adapterFor(incoming)
      if (adapter) this.buildSpareFrame(role, incoming, adapter)
    } catch {
      // A warm-up that fails costs the viewer nothing; the move it would have helped
      // simply pays full price.
    }
  }

  buildSpareFrame(role, incoming, adapter) {
    const frame = document.createElement("iframe")
    frame.id = FRAMES[role]
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
    //
    // One ask is not enough: a pause sent on the player's first report -- about four
    // seconds after the frame is built -- is ignored, while the same message a few seconds
    // later is obeyed. Measured 2026-09-05, and there is no announced moment when it starts
    // listening, so there is nothing to wait for exactly. Asking again each time it says it
    // has moved needs no such moment: it costs one message per five seconds, and it stops
    // of its own accord, because a player that has stopped stops reporting.
    //
    // Muted as well as paused, because there are seconds between the frame starting and the
    // first report it will act on, and something has to cover them. That used to be the
    // browser's own doing -- autoplay on a document nobody has touched is muted whatever
    // the page asks for -- but that is a policy about the document, not a promise to us, and
    // it lapses the moment the viewer clicks anything. Adopting a spare unmutes it, which is
    // what that was always for.
    this.spares[role].player = playerAdapterFor(adapter, frame, {
      onState: (state) => {
        const spare = this.spares[role]
        if (!spare || spare.seenAt === state.progress) return

        spare.seenAt = state.progress
        spare.player?.mute()
        spare.player?.pause()
      }
    })
  }

  // Which adapter drives the incoming page's player. Read from an attribute of its own
  // rather than off player-progress's value, which is what this used to do: that controller
  // is only on the page for somebody signed in, and it is not on the cable page at all --
  // so the lookup came back empty and the spare was built with nothing to stop it. A frame
  // nobody can pause is a frame playing out loud behind the one being watched. The adapter
  // belongs to the page's player, not to one of its readers.
  adapterFor(incoming) {
    const chrome = incoming.ownerDocument.getElementById("cinema-chrome")
    const name = chrome?.dataset.playerAdapter
    return isControllable(name) ? name : null
  }

  // Two embeds are the same thing playing when they differ only in where they would start.
  // Every provider spells that differently, hence the list; an address this cannot parse
  // falls back to comparing it whole, which is the old behaviour.
  samePlaying(a, b) {
    if (!a || !b) return false

    const withoutResume = (address) => {
      try {
        const url = new URL(address)
        ;["startAt", "start", "t"].forEach((param) => url.searchParams.delete(param))
        return url.toString()
      } catch {
        return address
      }
    }

    return withoutResume(a) === withoutResume(b)
  }

  // The move a spare was warmed for: no request, and no player to build. `apply` does the
  // adopting, so this only has to say we are leaving and hand it the page it already has --
  // and it stays right when the spare was fetched but never started, which is what happens
  // for a player this page cannot drive.
  promote(role) {
    const { page, url } = this.spares[role]

    this.dispatch("leaving", { target: document })
    this.apply(page, url)
  }

  discardSpares() {
    clearTimeout(this.warmingTimer)

    Object.keys(this.spares).forEach((role) => {
      this.spares[role].player?.destroy()
      document.getElementById(FRAMES[role])?.remove()
    })

    this.spares = {}
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
