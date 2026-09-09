import { Controller } from "@hotwired/stimulus"
import { playerAdapterFor, isControllable } from "services/player_adapter"

// Keeps a cable channel playing.
//
// The keyboard's transport is already gone and our own buttons cover the player's play and
// fullscreen controls, but its bar still carries a scrubber and two skip buttons, and
// clicking the picture pauses it. None of those can be reached into and removed: the frame
// is somebody else's document, and blocking pointer events on it wholesale would take the
// subtitles and the quality menu with them.
//
// So rather than stop the pause happening, this undoes it. A cable channel does not wait,
// and the schedule has not paused; a viewer who stops the film is only putting themselves
// out of step with the listing, with the guide, and with anybody else on the channel.
//
// Cheap, because a stopped player stops reporting: pausing produces one report and then
// silence, so this answers once rather than arguing every five seconds. Measured
// 2026-09-09 -- a pause reported at 1354s, a single play command, and playback continuing
// from 1354s.
//
// Nothing happens through a commercial break. Those come from YouTube, which this app has
// no way to drive at all -- see cable_filler_controller.
//
// Two things it deliberately does not do. It never touches a warmed spare, because it
// watches one named frame and the adapter ignores every other. And it stops once the
// programme has finished, so it cannot restart a film that has run out while the clock is
// still coming round to move on.
const GIVE_UP_AFTER = 5

export default class extends Controller {
  static values = { frame: String, adapter: String }

  connect() {
    if (!isControllable(this.adapterValue)) return

    const iframe = document.getElementById(this.frameValue)
    if (!iframe) return

    this.refused = 0
    this.player = playerAdapterFor(this.adapterValue, iframe, {
      onState: (state) => this.playerReported(state)
    })
  }

  disconnect() {
    this.player?.destroy()
  }

  playerReported({ event }) {
    // The film is over. Whatever it does now is the clock's business, not ours -- and a
    // player that has ended reports itself stopped, which is not somebody pausing.
    if (event === "completed") return this.stop()

    if (event !== "paused") {
      // Playing again, by our doing or their own. Start counting afresh, so a viewer who
      // pauses repeatedly is resisted every time rather than only the first few.
      this.refused = 0
      return
    }

    if (this.finished || this.refused >= GIVE_UP_AFTER) return

    // A player that will not restart after several asks is stopped for some reason of its
    // own -- out of buffer, or refused by the browser. Asking for ever would not fix it and
    // would leave a message going out every five seconds for the rest of the programme.
    this.refused += 1
    this.player?.play()
  }

  stop() {
    this.finished = true
  }
}
