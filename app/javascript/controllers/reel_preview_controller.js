import { Controller } from "@hotwired/stimulus"

// Says out loud what the commercial break hides.
//
// cable_filler does the same listening on /cable and answers it by putting the caption up:
// there, a reel that will not play is something to cover over as quickly as possible. Here
// it is the answer the page was opened to get, so the refusal is reported instead, with
// YouTube's own reason for it.
//
// The player will say why, but only to whoever asks. Its embed answers a `listening`
// handshake and then reports `onError` with a code. It is not listening until it has
// loaded, so ask more than once rather than trying to guess the moment.
const HANDSHAKES = [0, 700, 1800, 4000]

const REASONS = {
  2: "The embed address was rejected as malformed — check the id.",
  5: "YouTube's player could not handle it in this browser.",
  100: "The video is gone, private, or deleted.",
  101: "The uploader does not allow this video to be embedded.",
  150: "The uploader does not allow this video to be embedded."
}

export default class extends Controller {
  static targets = ["failure", "reason"]
  // Found by id rather than declared as a target: the frame is a sibling of the chrome,
  // the same way cable_filler reaches the player it watches.
  static values = { frame: String }

  connect() {
    this.heard = (event) => this.playerSpoke(event)
    window.addEventListener("message", this.heard)

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

    if (message?.event === "onError") this.report(message.info)
  }

  // The frame is left where it is rather than blanked. On /cable it is replaced because
  // YouTube's own error message is the thing being hidden; here it is evidence.
  report(code) {
    if (this.hasReasonTarget) {
      this.reasonTarget.textContent = REASONS[code] || `The player refused it (error ${code}).`
    }
    if (this.hasFailureTarget) this.failureTarget.hidden = false
  }
}
