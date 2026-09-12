import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

// The up-next card: what happens when a film ends and nobody has said otherwise.
//
// It is raised by `player-progress` a fixed lead before the end, not by the entry being
// marked watched -- a rewatch is marked from the first second, and would otherwise be
// offered the next entry over its opening titles.
//
// The card comes up over the picture, fullscreen included: it is rendered inside the
// element that goes fullscreen for exactly that reason. It counts for as long as the lead
// that raised it, so it reaches zero as the film does rather than at some other moment of
// its own -- one number, AppSetting#up_next_lead_seconds, passed in from the page.
//
// Cancelling the event is how player-progress knows the card took it. Where nothing does
// -- auto-next off for the channel, or a viewer who pressed Stop -- it hands the screen
// back instead, which is what it always did.
const DEFAULT_COUNTDOWN_SECONDS = 15

export default class extends Controller {
  static targets = ["countdown"]
  static values = {
    entryId: Number,
    channelId: Number,
    isOrdered: Boolean,
    // AppSetting#up_next_lead_seconds. From the page rather than a constant here, because
    // it is the same number that decided when this card was raised.
    seconds: Number
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
  //
  // Cancelled either way once it is ours, running or just raised -- the caller reads that
  // as "there is something on screen", and a second call while the card is already up must
  // not be read as nobody having taken it.
  start(event) {
    if (this.stopped) return

    event?.preventDefault()
    if (this.timer) return

    this.timeLeft = this.countdownSeconds
    this.render()
    this.modal.show()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  // Guarded rather than trusted: a 0 from a page that did not pass one would advance the
  // channel the instant the card appeared.
  get countdownSeconds() {
    return this.secondsValue > 0 ? this.secondsValue : DEFAULT_COUNTDOWN_SECONDS
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
