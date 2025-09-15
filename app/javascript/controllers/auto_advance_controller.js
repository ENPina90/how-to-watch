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
      const incrementUrl = `/entries/${this.entryIdValue}/increment_current?mode=watch`
      window.location.href = incrementUrl
    } else {
      // For unordered lists, go to random incomplete entry
      const shuffleUrl = `/entries/${this.entryIdValue}/shuffle_current?mode=watch`
      window.location.href = shuffleUrl
    }
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
