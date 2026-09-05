import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

// The up-next card: what happens when a film ends and nobody has said otherwise.
//
// It is raised by `player-progress` coming out of fullscreen with the film effectively
// over, not by the entry being marked watched -- a rewatch is marked from the first
// second, and would otherwise be offered the next entry over its opening titles.
//
// Thirty seconds is long enough to read and act on, and long enough to sit through a
// stinger, which is the thing most likely to be interrupted by getting this wrong.
const COUNTDOWN_SECONDS = 30

export default class extends Controller {
  static targets = ["countdown"]
  static values = {
    entryId: Number,
    channelId: Number,
    isOrdered: Boolean
  }

  connect() {
    this.modal = new Modal(this.element)
    // Dismissed any other way than the buttons -- escape, the close cross -- is still the
    // viewer saying no. Without this the countdown would run on behind a hidden card and
    // navigate out from under them.
    this.element.addEventListener("hidden.bs.modal", () => this.stop())
  }

  disconnect() {
    this.clearTimer()
  }

  // Once per visit. Somebody who stopped it does not want asking again every time they
  // step in and out of fullscreen, and a countdown already running does not restart.
  start() {
    if (this.stopped || this.timer) return

    this.timeLeft = COUNTDOWN_SECONDS
    this.render()
    this.modal.show()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  tick() {
    this.timeLeft -= 1
    this.render()

    if (this.timeLeft <= 0) this.advance()
  }

  render() {
    if (this.hasCountdownTarget) this.countdownTarget.textContent = this.timeLeft
  }

  // Stay here. The card goes and does not come back on this page: the viewer has said what
  // they want to happen next, which is nothing.
  stop() {
    this.stopped = true
    this.clearTimer()
    this.modal.hide()
  }

  advance() {
    this.clearTimer()

    // The channel is carried through because the entry being watched is not always in the
    // channel it is being watched *from*, and "next" means next on the one you are on.
    const channel = `mode=watch&channel=${this.channelIdValue}`

    // An ordered channel plays in its order; an unordered one picks something unseen, the
    // same as the shuffle button in the ring does.
    if (this.isOrderedValue) {
      this.submitPatch(`/entries/${this.entryIdValue}/increment_current?${channel}`)
    } else {
      this.submitPatch(`/entries/${this.entryIdValue}/shuffle_current?${channel}`)
    }
  }

  // Offered rather than performed: cinema-navigation answers this by fetching the next
  // entry and pasting it in, which keeps the player's frame and any fullscreen alive. If
  // nothing answers -- the controller absent, or an error before it could -- the old
  // route below still works, so the card is never a dead end.
  submitPatch(path) {
    const body = new FormData()
    body.append("_method", "patch")
    body.append("authenticity_token", this.csrfToken())

    const asked = this.dispatch("move", { target: document, cancelable: true, detail: { url: path, body: body } })
    if (!asked.defaultPrevented) this.navigateTo(path)
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  // The original route, kept as the fallback. Turbo is disabled on the watch page, so post
  // a real form rather than relying on data-turbo-method.
  navigateTo(path) {
    // The watch page asks "did you mean to leave?" whenever the frame has focus, which it
    // has for most of a film. This is the page leaving of its own accord, so say so --
    // otherwise the countdown reaches zero and stops there behind a prompt.
    window.leavingOnPurpose = true

    const form = document.createElement("form")
    form.method = "post"
    form.action = path
    form.style.display = "none"

    const override = document.createElement("input")
    override.type = "hidden"
    override.name = "_method"
    override.value = "patch"
    form.appendChild(override)

    const token = document.createElement("input")
    token.type = "hidden"
    token.name = "authenticity_token"
    token.value = this.csrfToken()
    form.appendChild(token)

    document.body.appendChild(form)
    form.submit()
  }

  clearTimer() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }
}
