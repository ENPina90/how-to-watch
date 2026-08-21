import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="auto-advance"
export default class extends Controller {
  static targets = ["countdown"]
  static values = {
    entryId: Number,
    listId: Number,
    isOrdered: Boolean
  }

  connect() {
    // Disable auto-start for debugging
    console.log('Auto-advance controller connected but not starting countdown')
    this.timeLeft = 3
    this.countdownTarget.textContent = this.timeLeft
    // this.startCountdown() // Disabled
  }

  startCountdown() {
    this.timer = setInterval(() => {
      this.timeLeft--
      this.countdownTarget.textContent = this.timeLeft

      if (this.timeLeft <= 0) {
        this.advance()
      }
    }, 1000)
  }

  cancel() {
    this.clearTimer()
    // Modal will be dismissed by Bootstrap
  }

  advance() {
    this.clearTimer()

    if (this.isOrderedValue) {
      // For ordered lists, go to next entry in sequence
      this.submitPatch(`/entries/${this.entryIdValue}/increment_current?mode=watch`)
    } else {
      // For unordered lists, go to random incomplete entry
      this.submitPatch(`/entries/${this.entryIdValue}/shuffle_current?mode=watch`)
    }
  }

  // These advance the user's position, so they are PATCH routes now. Turbo is disabled on
  // the watch page, so post a real form rather than relying on data-turbo-method.
  submitPatch(path) {
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
    token.value = document.querySelector('meta[name="csrf-token"]')?.content
    form.appendChild(token)

    document.body.appendChild(form)
    form.submit()
  }

  goToList() {
    this.clearTimer()
    window.location.href = `/lists/${this.listIdValue}`
  }

  clearTimer() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  disconnect() {
    this.clearTimer()
  }
}
