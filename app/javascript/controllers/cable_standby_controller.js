import { Controller } from "@hotwired/stimulus"

// Puts up "Please stand by" when what the channel is showing will not play.
//
// A channel is watched rather than worked through, so a dead frame is the worst thing it
// can show: YouTube's "This video is unavailable", vidsrc's "This media is unavailable", or
// a black rectangle. Those look like the site is broken. A stand-by card looks like the
// channel is having a moment, which is what a real one would put up. Nothing else changes:
// the clock still moves the channel on when the listing says to.
//
// It goes up on evidence, never on a hunch, because covering a film that was playing is a
// worse fault than the one being fixed. Two kinds count:
//
//   YouTube refuses      its embed answers a `listening` handshake and then reports `onError`:
//                        101 and 150 are embedding switched off, 100 gone or private, 2 a bad
//                        parameter, 5 the player itself. All mean the same thing here. Asked
//                        of commercial breaks and of YouTube programmes alike
//   vidsrc stays silent  a live vidsrc player posts its first PLAYER_EVENT in under a second
//                        (VIDSRC.md §6a). One that has said nothing after SILENCE_LIMIT has
//                        not started, and a title vidsrc has no file for never does
//
// The silence test is not applied to a frame adopted from a warmed spare. A spare that sat
// behind the live frame can play perfectly well and still post nothing -- fourteen reports
// in seventy seconds on one run and none in sixty on the next -- so its silence proves
// nothing. cinema-navigation marks the frames it adopts, and those are left alone.
//
// Nothing is marked broken on the strength of any of this. A refusal can be momentary, and
// an entry struck off after one bad minute would be a worse fault than a minute of card.
//
// The card lives outside the chrome, so a move between channels does not replace it -- this
// controller does connect again, though, and sets it for the programme it has arrived at.
const HANDSHAKES = [0, 700, 1800, 4000]
const SILENCE_LIMIT = 20000

export default class extends Controller {
  // Found by id rather than declared as targets: this rides on the chrome, and both the
  // frame and the card are the chrome's siblings inside the screen. player-keys and
  // cable-clock reach the player the same way and for the same reason.
  static values = { frame: String, card: String, youtube: Boolean, silence: Boolean }

  connect() {
    this.timers = []
    // Whatever the last programme needed, this one starts uncovered.
    if (this.card) this.card.hidden = true

    this.heard = (event) => this.playerSpoke(event)
    window.addEventListener("message", this.heard)

    // The player only reports once asked, and it is not listening until it has loaded --
    // so ask more than once rather than trying to guess the moment.
    if (this.youtubeValue) this.timers = HANDSHAKES.map((delay) => setTimeout(() => this.ask(), delay))

    if (this.silenceValue && this.frame?.dataset.adopted !== "true") this.listenForSilence()

    // A player of our own says so outright. Neither test above applies to it -- there is no
    // handshake to answer and no silence to measure, because it is not an embed -- but a
    // <video> that cannot play its file fires `error`, which is better evidence than either
    // and arrives without being asked. Without this a dead MEGA programme showed a black
    // rectangle where every other provider gets the card.
    if (this.frame?.tagName === "VIDEO") {
      this.failed = () => this.giveUp()
      this.frame.addEventListener("error", this.failed)
    }
  }

  disconnect() {
    if (this.failed) this.frame?.removeEventListener("error", this.failed)
    if (this.heard) window.removeEventListener("message", this.heard)
    if (this.shown) document.removeEventListener("visibilitychange", this.shown)
    this.timers.forEach(clearTimeout)
    clearTimeout(this.silenceTimer)
  }

  get frame() {
    return document.getElementById(this.frameValue)
  }

  get card() {
    return document.getElementById(this.cardValue)
  }

  ask() {
    try {
      this.frame?.contentWindow?.postMessage(JSON.stringify({ event: "listening" }), "*")
    } catch {
      // A frame mid-navigation. The next handshake will find it.
    }
  }

  // Counted only while the page is on screen. A tab opened in the background may not load
  // its frame at all until it is looked at, and that is not the player failing.
  listenForSilence() {
    const start = () => {
      clearTimeout(this.silenceTimer)
      if (document.visibilityState !== "visible" || this.spoke) return

      this.silenceTimer = setTimeout(() => { if (!this.spoke) this.giveUp() }, SILENCE_LIMIT)
    }

    this.shown = start
    document.addEventListener("visibilitychange", start)
    start()
  }

  playerSpoke(event) {
    if (!this.frame || event.source !== this.frame.contentWindow) return

    // vidsrc posts objects, YouTube posts JSON strings.
    if (event.data?.type === "PLAYER_EVENT") {
      this.spoke = true
      clearTimeout(this.silenceTimer)
      return
    }

    let message
    try { message = JSON.parse(event.data) } catch { return }

    if (message?.event === "onError") this.giveUp()
  }

  // The card was rendered with the page and is simply uncovered, so there is nothing to
  // build at the moment it is needed. The frame goes blank rather than staying on the
  // provider's own error -- which is the thing being hidden, and may still be making noise.
  giveUp() {
    const card = this.card
    if (!card) return

    card.hidden = false
    if (!this.frame) return

    // Blanked so the provider's own error page is not left showing behind the card -- that
    // is the thing being hidden, and it may still be making noise. A <video> is emptied
    // rather than pointed at about:blank: handed a document address it would only raise
    // the same error again, and the card is already up.
    if (this.frame.tagName === "VIDEO") {
      this.frame.removeAttribute("src")
      this.frame.load()
    } else {
      this.frame.src = "about:blank"
    }
  }
}
