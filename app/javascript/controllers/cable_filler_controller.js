import { Controller } from "@hotwired/stimulus"

// Watches the commercial break for a YouTube embed that will not play.
//
// The reels are somebody else's videos on somebody else's service, and any of them can stop
// being playable between one break and the next: taken down, made private, embedding
// switched off, or simply refused for the moment. What the viewer gets then is a black
// rectangle reading "This video is unavailable" for the whole break, which is worse than
// having no adverts at all -- it looks like the channel is broken rather than between
// programmes.
//
// The player will say so, but only to whoever asks. YouTube's embed answers a `listening`
// handshake and then reports `onError` with a code: 101 and 150 are embedding disabled by
// the owner, 100 is gone or private, 2 is a bad parameter, 5 is the player itself. Any of
// them mean the same thing here, so none is treated differently -- there is one thing to do
// about it, which is put the caption up instead.
//
// Nothing is marked as broken on the strength of this. A refusal can be momentary, and a
// reel struck off after one bad minute would be a worse fault than the one being fixed.
const HANDSHAKES = [0, 700, 1800, 4000]

export default class extends Controller {
  // Found by id rather than declared as targets: this rides on the chrome, and both the
  // frame and the caption are the chrome's siblings inside the screen. player-keys and
  // cable-clock reach the player the same way and for the same reason.
  static values = { frame: String, card: String }

  connect() {
    this.heard = (event) => this.playerSpoke(event)
    window.addEventListener("message", this.heard)

    // The player only reports once asked, and it is not listening until it has loaded --
    // so ask more than once rather than trying to guess the moment.
    this.timers = HANDSHAKES.map((delay) => setTimeout(() => this.ask(), delay))
  }

  disconnect() {
    window.removeEventListener("message", this.heard)
    this.timers.forEach(clearTimeout)
  }

  get frame() {
    return document.getElementById(this.frameValue)
  }

  ask() {
    try {
      this.frame?.contentWindow?.postMessage(JSON.stringify({ event: "listening" }), "*")
    } catch {
      // A frame mid-navigation. The next handshake will find it.
    }
  }

  playerSpoke(event) {
    if (!this.frame || event.source !== this.frame.contentWindow) return

    let message
    try { message = JSON.parse(event.data) } catch { return }

    if (message?.event === "onError") this.giveUp()
  }

  // The caption was rendered with the page and is simply uncovered, so there is nothing to
  // build at the moment it is needed. The frame goes blank rather than staying on YouTube's
  // own error, which is the thing being hidden.
  giveUp() {
    const card = document.getElementById(this.cardValue)
    if (!card) return

    card.hidden = false
    if (this.frame) this.frame.src = "about:blank"
  }
}
