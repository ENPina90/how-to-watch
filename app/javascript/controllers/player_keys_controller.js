import { Controller } from "@hotwired/stimulus"
import { playerAdapterFor, isControllable } from "services/player_adapter"

// Play, pause and seek from the keyboard.
//
// The player has its own shortcuts and they stopped working when fullscreen moved from the
// frame to the container around it (cinema_fullscreen_controller.js). Keys go to the
// focused document, and in fullscreen that is now ours rather than theirs, so nothing
// reaches the player unless this page forwards it.
//
// Space was worse than merely dead. Our fullscreen button keeps focus after a click, and
// the browser activates the focused control before any of this is consulted, so pressing
// space left fullscreen instead of pausing.
const SEEK_SECONDS = 5

export default class extends Controller {
  static values = { frame: String, adapter: String }

  connect() {
    if (!isControllable(this.adapterValue)) return

    const iframe = document.getElementById(this.frameValue)
    if (!iframe) return

    this.player = playerAdapterFor(this.adapterValue, iframe, {
      onState: (state) => this.playerReported(state),
    })

    // On the document, not on this element: a keystroke goes to whatever has focus, which
    // is rarely inside this element and is never inside the frame the film is in.
    this.keyed = (event) => this.handle(event)
    document.addEventListener("keydown", this.keyed)
  }

  disconnect() {
    document.removeEventListener("keydown", this.keyed)
    this.player?.destroy?.()
  }

  playerReported(state) {
    this.progress = state.progress
    this.reportedAt = Date.now()
    this.playing = state.status === "playing"

    // Once it reports back from somewhere near where it was sent, the seek has landed and
    // the player's own position is the better one again.
    if (this.assumed != null && Math.abs(state.progress - this.assumed) < SEEK_SECONDS) {
      this.assumed = null
    }
  }

  handle(event) {
    if (!this.player || this.busyElsewhere(event)) return
    if (event.metaKey || event.ctrlKey || event.altKey) return

    switch (event.key) {
      case " ":
      case "k":
        return this.togglePlay(event)
      case "ArrowLeft":
        return this.seekBy(-SEEK_SECONDS, event)
      case "ArrowRight":
        return this.seekBy(SEEK_SECONDS, event)
    }
  }

  // Somewhere a keystroke means something else: a field being typed into, or an open
  // dialog -- the review prompt, the source pickers, the up-next card. Space belongs to
  // whatever is being asked rather than to the film behind it.
  busyElsewhere({ target }) {
    if (target instanceof HTMLElement && target.isContentEditable) return true
    if (target instanceof HTMLElement && /^(input|textarea|select)$/i.test(target.tagName)) return true

    return Boolean(document.querySelector(".modal.show"))
  }

  togglePlay(event) {
    // Stops the page scrolling, and stops the browser activating whatever button still has
    // focus -- which is how space came to leave fullscreen.
    event.preventDefault()
    this.dropFocus()

    if (this.playing) this.player.pause()
    else this.player.play()

    // Assumed rather than awaited: two presses inside one report would otherwise both be
    // read as the same direction. The next report corrects it either way.
    this.playing = !this.playing
  }

  // A control that has been clicked keeps focus, and every later keystroke goes to it
  // first. Nothing on this page wants a second press, so focus goes back to the document.
  dropFocus() {
    const focused = document.activeElement

    if (focused instanceof HTMLElement && focused !== document.body) focused.blur()
  }

  seekBy(delta, event) {
    event.preventDefault()

    const target = Math.max(0, this.positionNow() + delta)
    // The protocol's seek is absolute, so successive presses have to accumulate here.
    // Reports arrive about every five seconds, and three taps inside one of them would
    // otherwise all seek from the same place and move the film five seconds in total.
    //
    // The player's own handler matches `seek([+-]?)([0-9]+)`, so it may well take a
    // relative `seek-5` and make all of this unnecessary. The sign has never been tried,
    // and guessing wrong would jump the film to five seconds in rather than back five.
    this.assumed = target
    this.assumedAt = Date.now()
    this.player.seek(target)
  }

  // Where the film is now: the last position it reported, carried forward by the clock if
  // it has been playing since. Seeking from a five-second-old position lands somewhere
  // nobody asked for.
  positionNow() {
    const base = this.assumed ?? this.progress
    if (base == null) return 0

    const since = this.playing ? (Date.now() - (this.assumed != null ? this.assumedAt : this.reportedAt)) / 1000 : 0

    return base + since
  }
}
