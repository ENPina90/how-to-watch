import { Controller } from "@hotwired/stimulus"

// The channel banner, and the two arrows that look along the schedule without touching it.
//
// Left and right walk this channel's running order -- what was on before, what is on next
// and at what time -- and change nothing. That is the whole point of them: on a cable
// channel there is nothing to skip to, because the schedule decides what plays and when, so
// an arrow that moved the programme would be lying about what a channel is. It answers the
// question the arrows are actually asked, which is "what did I miss" and "what is coming".
//
// It falls back to what is really on after a moment, for the same reason the guide's panel
// does: the banner is a caption for the picture underneath it, and the picture has not
// moved. Anything else leaves the screen describing a programme that is not playing.
//
// Up and down are not here at all. They change channel, which is a navigation, so they are
// ordinary cinema-move links and cinema-navigation answers them.
const REVERT_AFTER = 6000

export default class extends Controller {
  static targets = ["title", "context", "when", "label", "schedule"]
  static classes = ["showing"]

  connect() {
    this.slots = [...this.scheduleTarget.children].map((node) => ({ ...node.dataset }))
    this.at = this.slots.findIndex((slot) => slot.slotCurrent === "true")
    // No schedule to walk -- an off-air channel, or one whose listing did not render.
    if (this.at < 0) this.at = 0
    this.now = this.at

    this.show()
  }

  disconnect() {
    clearTimeout(this.revertTimer)
  }

  earlier() {
    this.step(-1)
  }

  later() {
    this.step(1)
  }

  step(by) {
    const to = this.at + by
    if (to < 0 || to >= this.slots.length) return

    this.at = to
    this.show()
    this.rest()
  }

  // Back to what is actually playing.
  revert() {
    clearTimeout(this.revertTimer)
    this.at = this.now
    this.show()
  }

  rest() {
    clearTimeout(this.revertTimer)
    if (this.at !== this.now) this.revertTimer = setTimeout(() => this.revert(), REVERT_AFTER)
  }

  show() {
    const slot = this.slots[this.at]
    if (!slot) return

    const peeking = this.at !== this.now

    this.titleTarget.textContent = slot.slotTitle ? `“${slot.slotTitle}”` : ""
    this.titleTarget.href = slot.slotUrl ?? "#"
    this.contextTarget.textContent = slot.slotContext ?? ""
    this.whenTarget.textContent = this.span(slot)
    // Says which way you are looking, so a time on its own is never mistaken for now.
    this.labelTarget.textContent = peeking ? (this.at < this.now ? "Earlier" : "Next up") : "On now"

    this.element.classList.toggle(this.showingClass, peeking)
    // An arrow at the end of what was rendered is spent, and should look it.
    this.mark(".cable-hud__key--left", this.at === 0)
    this.mark(".cable-hud__key--right", this.at === this.slots.length - 1)
  }

  mark(selector, spent) {
    const key = this.element.querySelector(selector)
    if (key) key.disabled = spent
  }

  // In the viewer's own zone, like every other time on this page: the schedule is a set of
  // instants and what time they are belongs to whoever is looking at them.
  span({ slotStart, slotEnd }) {
    if (!slotStart || !slotEnd) return ""

    const clock = new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" })
    return `${clock.format(new Date(Number(slotStart)))} – ${clock.format(new Date(Number(slotEnd)))}`
  }
}
