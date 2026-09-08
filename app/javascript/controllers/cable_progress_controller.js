import { Controller } from "@hotwired/stimulus"

// The bar under "On now", filled from the clock.
//
// Nothing here asks the player anything. How far through a cable programme is depends on
// what time it is and not on where any one viewer's player has got to -- somebody who
// paused is behind the channel, and the bar should go on showing where the channel is.
//
// Once every ten seconds: the bar is a few hundred pixels wide, so a finer tick would
// repaint the same picture.
const TICK = 10000

export default class extends Controller {
  static targets = ["fill", "remaining", "span", "upcoming"]
  static values = { startsAt: String, endsAt: String }

  connect() {
    this.startsAt = Date.parse(this.startsAtValue)
    this.endsAt = Date.parse(this.endsAtValue)
    if (Number.isNaN(this.startsAt) || Number.isNaN(this.endsAt)) return

    this.localise()
    this.render()
    this.timer = setInterval(() => this.render(), TICK)
  }

  // The times are rendered in the schedule's zone, because the server cannot know where the
  // viewer is. Here we do, so they are rewritten into local time -- a listing should agree
  // with the clock in the room. The instants themselves never move; only how they read.
  localise() {
    const clock = new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" })

    if (this.hasSpanTarget) {
      this.spanTarget.textContent =
        `${clock.format(new Date(this.startsAt))} – ${clock.format(new Date(this.endsAt))}`
    }

    this.upcomingTargets.forEach((element) => {
      const at = Number(element.dataset.at)
      if (at) element.textContent = clock.format(new Date(at))
    })
  }

  disconnect() {
    clearInterval(this.timer)
  }

  render() {
    const total = this.endsAt - this.startsAt
    if (total <= 0) return

    const elapsed = Math.min(Math.max(Date.now() - this.startsAt, 0), total)

    if (this.hasFillTarget) this.fillTarget.style.width = `${(elapsed / total) * 100}%`
    if (this.hasRemainingTarget) this.remainingTarget.textContent = this.label(total - elapsed)
  }

  // Rounded up, because "0 min left" reads as over while it is still playing.
  label(remaining) {
    const minutes = Math.ceil(remaining / 60000)
    if (minutes <= 0) return ""

    return `· ${minutes} min left`
  }
}
