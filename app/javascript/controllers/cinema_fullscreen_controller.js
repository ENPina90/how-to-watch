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
// Idle hiding only applies in fullscreen: windowed, this page has always shown its
// controls and there is no reason to start hiding them.
const IDLE_DELAY = 2500

export default class extends Controller {
  static classes = ["idle"]

  connect() {
    this.wake = () => this.stirred()
    this.fullscreenChanged = () => this.fullscreenMoved()

    document.addEventListener("fullscreenchange", this.fullscreenChanged)
    document.addEventListener("webkitfullscreenchange", this.fullscreenChanged)
  }

  disconnect() {
    this.stopWatchingForIdle()
    document.removeEventListener("fullscreenchange", this.fullscreenChanged)
    document.removeEventListener("webkitfullscreenchange", this.fullscreenChanged)
  }

  toggle() {
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
    if (this.fullscreen) this.startWatchingForIdle()
    else this.stopWatchingForIdle()
  }

  // The player is a cross-origin frame, so a mouse moving over the picture tells us
  // nothing -- those events belong to its document. What does reach us is the mouse
  // arriving anywhere else on the page, and any key. That is enough: the controls sit
  // around the picture, so reaching for one is a move towards us.
  startWatchingForIdle() {
    this.element.addEventListener("mousemove", this.wake)
    this.element.addEventListener("keydown", this.wake)
    this.stirred()
  }

  stopWatchingForIdle() {
    this.element.removeEventListener("mousemove", this.wake)
    this.element.removeEventListener("keydown", this.wake)
    clearTimeout(this.idleTimer)
    this.element.classList.remove(...this.idleClasses)
  }

  stirred() {
    clearTimeout(this.idleTimer)
    this.element.classList.remove(...this.idleClasses)
    this.idleTimer = setTimeout(() => this.element.classList.add(...this.idleClasses), IDLE_DELAY)
  }
}
