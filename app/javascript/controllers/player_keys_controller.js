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

// Keys the player used to answer for itself:
//
//   space / k   play or pause
//   left/right  seek five seconds
//   f           fullscreen -- ours, not the player's, whose own `f` went dead with the
//               permission (cinema_fullscreen_controller.js)
//   m           mute

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
    this.playing = state.status === "playing"
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
      case "f":
        return this.toggleFullscreen(event)
      case "m":
        return this.toggleMute(event)
    }
  }

  // Dispatched rather than called: fullscreen belongs to the screen element and its
  // controller sits on that, not here. Synchronous, so the keystroke is still the user
  // gesture the browser requires before it will grant the screen.
  toggleFullscreen(event) {
    event.preventDefault()
    this.dispatch("fullscreen", { target: document })
  }

  // Tracked here because the player reports status, progress and duration and says nothing
  // about volume, so there is no answer to ask for.
  //
  // Assumed to start unmuted, which is what it is: either the viewer pressed play, or the
  // frame was warmed in the background and cinema-navigation unmuted it on the way in. A
  // player left muted by the browser and never promoted is the one case where the first
  // press is swallowed and the second takes effect.
  toggleMute(event) {
    event.preventDefault()

    if (this.muted) this.player.unmute()
    else this.player.mute()

    this.muted = !this.muted
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

  // Relative, so the player applies it to where the film actually is. Successive taps
  // accumulate on their side and nothing here has to guess at a position between reports.
  seekBy(delta, event) {
    event.preventDefault()
    this.player.seekBy(delta)
  }
}
