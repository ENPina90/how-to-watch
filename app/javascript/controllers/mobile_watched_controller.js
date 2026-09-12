import { Controller } from "@hotwired/stimulus"

// The eye on a card in the phone view: watched, or not.
//
// The same entries#complete route every other card in the app uses, which is a toggle
// already. Nothing moves before the write lands -- a mark that flipped optimistically
// would be a lie whenever the write failed, and marking something watched is most of what
// this half of the app is for.
export default class extends Controller {
  static values = { entryId: Number, on: Boolean }

  async toggle() {
    if (this.working) return

    this.working = true

    try {
      const response = await fetch(`/entries/${this.entryIdValue}/complete`, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
          Accept: "application/json"
        }
      })
      if (!response.ok) return this.refused()

      this.onValue = !this.onValue
      this.draw()
    } catch {
      this.refused()
    } finally {
      this.working = false
    }
  }

  draw() {
    const icon = this.element.querySelector("i")

    icon.classList.toggle("fa-solid", this.onValue)
    icon.classList.toggle("fa-regular", !this.onValue)
    this.element.classList.toggle("m-card__mark--on", this.onValue)
    this.element.title = this.onValue ? "Watched" : "Mark as watched"
    // The poster dims when the film has been seen, so the card as a whole has to hear
    // about it rather than only the eye.
    this.element.closest(".m-card")?.classList.toggle("m-card--watched", this.onValue)
  }

  // It would not take. Shakes its head and stays as it was, which is all this can usefully
  // say about a request that failed.
  refused() {
    this.element.classList.add("m-card__mark--refused")
    setTimeout(() => this.element.classList.remove("m-card__mark--refused"), 1200)
  }
}
