import { Controller } from "@hotwired/stimulus"

// Fullscreen that belongs to the page rather than to the frame.
//
// The obvious way -- let the embedded player take the screen -- hands the whole display to
// a third party: the ring of controls, the channel name, the up-next card and everything
// else this page is for all disappear, because they are not inside the element that went
// fullscreen. Putting the *container* full-screen keeps them, and the player simply fills
// it.
//
// Which is why the frame no longer carries `allowfullscreen`. Two routes to fullscreen
// would be worse than one, and the player's own is the worse one; without the permission
// its button, its `f` shortcut and its double-click are all inert, because what is denied
// is the capability rather than any particular way of asking for it. Measured 2026-09-05:
// playback is unaffected and the dead button does nothing visible.
//
// Taking it back afterwards is not an option -- moving fullscreen from the frame to an
// ancestor is refused ("Permissions check failed") without a fresh gesture of our own, and
// their button's click belongs to their document. So the permission has to be withheld up
// front rather than corrected later.
//
// Idle hiding in fullscreen: the picture is the whole screen, so anything of ours on top
// of it is in the way once nobody is using it.
//
// Windowed it is off by default -- the watch page has always shown its controls there and
// there is no reason to start hiding them -- but a page can ask for it. /cable does: it is
// a channel playing to a room rather than a page being worked through, so its chrome is a
// caption that has said its piece, not a set of controls somebody is about to reach for.
// Such a page sets its own delay, because the two cases are not the same wait: in
// fullscreen you have just moved the mouse to get there, and windowed you may be reading.
const IDLE_DELAY = 2500

export default class extends Controller {
  static classes = ["idle"]
  static values = {
    // Hide the chrome windowed too, not only in fullscreen.
    always: Boolean,
    // How long to leave it before hiding, in milliseconds. Zero means the built-in wait.
    idleDelay: Number
  }

  connect() {
    this.wake = () => this.stirred()
    this.fullscreenChanged = () => this.fullscreenMoved()

    document.addEventListener("fullscreenchange", this.fullscreenChanged)
    document.addEventListener("webkitfullscreenchange", this.fullscreenChanged)

    if (this.alwaysValue) this.startWatchingForIdle()
  }

  get delay() {
    return this.idleDelayValue > 0 ? this.idleDelayValue : IDLE_DELAY
  }

  disconnect() {
    this.stopWatchingForIdle()
    document.removeEventListener("fullscreenchange", this.fullscreenChanged)
    document.removeEventListener("webkitfullscreenchange", this.fullscreenChanged)
  }

  toggle(event) {
    // The button keeps focus after a click, and the browser hands later key presses to the
    // focused control before anything else sees them -- which is how space came to leave
    // fullscreen instead of pausing the film. See player_keys_controller.js.
    event?.currentTarget?.blur?.()

    if (this.fullscreen) this.exit()
    else this.enter()
  }

  enter() {
    const request = this.element.requestFullscreen || this.element.webkitRequestFullscreen
    // Refused on a browser that will not grant it, or with no gesture behind the call.
    // Nothing to do but leave the page as it is.
    try { request.call(this.element)?.catch(() => {}) } catch { /* not available */ }
  }

  exit() {
    const release = document.exitFullscreen || document.webkitExitFullscreen
    try { release.call(document)?.catch(() => {}) } catch { /* not available */ }
  }

  get fullscreen() {
    const element = document.fullscreenElement || document.webkitFullscreenElement
    return element === this.element
  }

  fullscreenMoved() {
    // A page that hides its chrome windowed as well never stops watching -- leaving
    // fullscreen is not a reason to bring it back and keep it there.
    if (this.fullscreen || this.alwaysValue) this.startWatchingForIdle()
    else this.stopWatchingForIdle()
  }

  // A mouse moving over the picture is invisible from here: pointer events inside a
  // cross-origin frame belong to its document. In a window that hardly matters, because
  // the page surrounds the picture -- but in fullscreen the picture is the whole screen,
  // and there is nowhere else for the mouse to be.
  //
  // So while the chrome is hidden the frame stops taking pointer events (see the idle
  // rule in _cinema.scss) and movement falls through to the screen, where this can see it.
  // Removing the class hands them back in the same breath.
  startWatchingForIdle() {
    if (this.watching) return
    this.watching = true

    this.element.addEventListener("mousemove", this.wake)
    this.element.addEventListener("keydown", this.wake)
    this.stirred()
  }

  stopWatchingForIdle() {
    this.watching = false
    this.element.removeEventListener("mousemove", this.wake)
    this.element.removeEventListener("keydown", this.wake)
    clearTimeout(this.idleTimer)
    this.element.classList.remove(...this.idleClasses)
  }

  stirred() {
    clearTimeout(this.idleTimer)
    this.element.classList.remove(...this.idleClasses)
    this.idleTimer = setTimeout(() => this.element.classList.add(...this.idleClasses), this.delay)
  }
}
