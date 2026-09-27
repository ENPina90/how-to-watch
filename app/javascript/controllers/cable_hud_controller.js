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
  static targets = ["title", "context", "when", "label", "schedule", "start", "favorite", "favoriteIcon"]
  static classes = ["showing"]
  static values = { token: String }

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
    // The same film, said as a button -- but from the top, where the title resumes. It
    // follows the arrows rather than staying on what is playing: the banner describes one
    // programme at a time, and this offers to start whichever one that is.
    this.startTarget.href = slot.slotStartUrl ?? "#"
    this.startTarget.hidden = !slot.slotStartUrl
    if (this.hasFavoriteTarget) {
      this.favoriteTarget.hidden = !slot.slotEntryId
      this.showFavorite(slot.slotFavorited === "true")
    }
    this.contextTarget.textContent = slot.slotContext ?? ""
    this.whenTarget.textContent = this.span(slot)
    // Says which way you are looking, so a time on its own is never mistaken for now.
    this.labelTarget.textContent = peeking ? (this.at < this.now ? "Earlier" : "Next up") : "On now"

    this.element.classList.toggle(this.showingClass, peeking)
    // An arrow at the end of what was rendered is spent, and should look it.
    this.mark(".cable-hud__key--left", this.at === 0)
    this.mark(".cable-hud__key--right", this.at === this.slots.length - 1)
  }

  // In the member's own favourites channel, or not -- the guide's heart, on the same route
  // and the same terms. Nothing is drawn until the server answers: a heart that filled
  // before the write landed would be a lie whenever the write failed.
  async favorite() {
    const slot = this.slots[this.at]
    const id = slot?.slotEntryId
    if (!id || this.favoriting) return

    const on = slot.slotFavorited !== "true"
    this.favoriting = true
    // Pressing it is reading the banner, so it should not snap back to what is on mid-press.
    this.rest()

    try {
      const response = await fetch(`/entries/${encodeURIComponent(id)}/favorite`, {
        method: on ? "POST" : "DELETE",
        headers: { "X-CSRF-Token": this.tokenValue, Accept: "application/json" }
      })
      if (!response.ok) return this.favoriteRefused()

      // Every slot showing this film, since a channel repeats itself within a running order
      // and the heart should not revert on the next arrow press.
      this.slots.filter((other) => other.slotEntryId === id)
        .forEach((other) => { other.slotFavorited = String(on) })
      if (this.slots[this.at]?.slotEntryId === id) this.showFavorite(on)
    } catch {
      this.favoriteRefused()
    } finally {
      this.favoriting = false
    }
  }

  // Hollow for off, solid for on -- the same pair of glyphs the guide uses.
  showFavorite(on) {
    this.favoriteIconTarget.classList.toggle("fa-solid", on)
    this.favoriteIconTarget.classList.toggle("fa-regular", !on)
    this.favoriteTarget.classList.toggle("cable-hud__action--on", on)
    this.favoriteTarget.setAttribute("aria-label", on ? "In your favourites -- press to remove" : "Add to my favourites")
  }

  favoriteRefused() {
    this.favoriteTarget.classList.add("cable-hud__action--refused")
    setTimeout(() => this.favoriteTarget.classList.remove("cable-hud__action--refused"), 1200)
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
