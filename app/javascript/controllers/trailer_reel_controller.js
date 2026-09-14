import { Controller } from "@hotwired/stimulus"

// Trailers, one after another: /trailers, and channel 0 on /cable.
//
// There is no schedule to say when a trailer is over, so the player has to. YouTube's embed
// answers a `listening` handshake -- the same one cable-filler uses to hear a reel refuse --
// and from then on reports its state, 0 being the end of the video. onStateChange is asked
// for by name as well, because the embed has said "ended" both ways and there is no knowing
// which it will use this year.
//
// A refusal moves on too, and is commoner than it sounds: these are TMDB's links, some of
// them years old, and a trailer taken down since is a black frame reading "Video
// unavailable" that nobody wants to sit through.
//
// The move is offered rather than performed, as cable-clock offers its own: cinema-navigation
// fetches the next page and pastes it in, so the screen and any fullscreen survive. If
// nothing answers, it is an ordinary navigation to the same place.
const HANDSHAKES = [0, 700, 1800, 4000]
const ENDED = 0

// A player that never says a word -- a blocked script, an extension eating the messages --
// would otherwise leave the page on a finished trailer for good. Longer than any trailer,
// and dropped the moment the player speaks: after that it will say when it is done, and a
// viewer who paused one should not be moved on from under it.
const SILENCE_LIMIT = 5 * 60 * 1000

export default class extends Controller {
  static values = { frame: String, url: String }

  connect() {
    this.heard = (event) => this.playerSpoke(event)
    this.keyed = (event) => this.keyPressed(event)
    window.addEventListener("message", this.heard)
    document.addEventListener("keydown", this.keyed)

    // Not listening until it has loaded, so ask more than once rather than guess the moment.
    this.timers = HANDSHAKES.map((delay) => setTimeout(() => this.ask(), delay))
    this.silence = setTimeout(() => this.next(), SILENCE_LIMIT)
  }

  disconnect() {
    window.removeEventListener("message", this.heard)
    document.removeEventListener("keydown", this.keyed)
    this.timers.forEach(clearTimeout)
    clearTimeout(this.silence)
  }

  get frame() {
    return document.getElementById(this.frameValue)
  }

  ask() {
    const player = this.frame?.contentWindow
    if (!player) return

    try {
      player.postMessage(JSON.stringify({ event: "listening", id: this.frameValue }), "*")
      player.postMessage(JSON.stringify({ event: "command", func: "addEventListener", args: ["onStateChange"] }), "*")
    } catch {
      // A frame mid-navigation. The next handshake will find it.
    }
  }

  playerSpoke(event) {
    if (!this.frame || event.source !== this.frame.contentWindow) return

    let message
    try { message = JSON.parse(event.data) } catch { return }

    clearTimeout(this.silence)

    if (message?.event === "onError") return this.next()
    if (message?.event === "onStateChange" && message.info === ENDED) return this.next()
    if (message?.event === "infoDelivery" && message.info?.playerState === ENDED) this.next()
  }

  // Right is "the next one", the way it walks forward along a channel's running order. The
  // guide claims the arrows for itself while it is up, and takes them before this sees them.
  keyPressed(event) {
    if (event.key !== "ArrowRight" || event.defaultPrevented) return
    if (event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return

    const { target } = event
    if (target instanceof HTMLElement &&
        (target.isContentEditable || /^(input|textarea|select)$/i.test(target.tagName))) return

    event.preventDefault()
    this.next()
  }

  // Once. An end and an error can both arrive, and a second move while the first is in flight
  // would race two trailers into the same page.
  next() {
    if (this.moved) return
    this.moved = true
    this.timers.forEach(clearTimeout)
    clearTimeout(this.silence)

    const asked = this.dispatch("next", {
      target: document, cancelable: true, detail: { url: this.urlValue }
    })
    if (asked.defaultPrevented) return

    // The page asks "did you mean to leave?" whenever the frame has focus.
    window.leavingOnPurpose = true
    window.location.assign(this.urlValue)
  }
}
