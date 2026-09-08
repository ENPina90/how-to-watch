import { Controller } from "@hotwired/stimulus"
import { playerAdapterFor, isControllable } from "services/player_adapter"

// When a cable programme is over, the next one is already on.
//
// This is the piece that makes /cable a channel rather than a playlist. On the watch page a
// film ending raises the up-next card and asks; here there is nothing to ask, because the
// schedule already decided and the next programme has started whether anybody moved or not.
//
// It moves for two reasons, and they are not the same reason:
//
//   the clock reaching the slot's end time. This is the authority. The schedule is the same
//   for everybody, so the moment one programme gives way to the next has to be a fact about
//   the time rather than about this viewer's player -- somebody who paused for ten minutes
//   rejoins the channel where the channel is, not where they left it;
//
//   the player saying it finished, which only happens on a provider with an adapter. The
//   catalogue's runtime is a minute or two out often enough that waiting for the clock would
//   leave a finished player sitting on a black frame. Moving early lands on the next
//   programme at its own offset, which is zero or near it, so nothing is skipped.
//
// The move itself is cinema-navigation's, offered rather than performed for the same reason
// the up-next card offers it: if that controller is not there, the fallback is an ordinary
// navigation to the same URL and the channel still changes programme.
export default class extends Controller {
  static values = {
    // The channel's own path. Asked again when the programme ends, and it answers with
    // whatever is on by then -- so a tab left open overnight catches up in one request
    // rather than stepping through everything it slept through.
    url: String,
    // When this programme ends, from the server, in UTC. The client's clock may be wrong;
    // what matters is that it is wrong by the same amount for the whole page.
    endsAt: String,
    adapter: String,
    frame: String
  }

  connect() {
    this.scheduleMove()
    this.watchPlayer()
  }

  disconnect() {
    clearTimeout(this.timer)
    this.player?.destroy()
  }

  scheduleMove() {
    const endsAt = Date.parse(this.endsAtValue)
    if (Number.isNaN(endsAt)) return

    // A programme whose end has already passed by the time the page renders -- a slow
    // request landing in the last second of a slot. Move at once rather than never.
    //
    // setTimeout is clamped to a 32-bit millisecond count, so anything past ~24 days would
    // fire immediately; nothing here is ever that long, but the guard costs a line.
    const wait = Math.min(Math.max(endsAt - Date.now(), 0), 2147483647)
    this.timer = setTimeout(() => this.move(), wait)
  }

  // Only providers with an adapter say anything at all. On the rest this finds nothing to
  // listen to and the clock does the whole job, which is the intended behaviour rather than
  // a gap -- the same as position tracking on the watch page.
  watchPlayer() {
    if (!isControllable(this.adapterValue)) return

    const iframe = document.getElementById(this.frameValue)
    if (!iframe) return

    this.player = playerAdapterFor(this.adapterValue, iframe, {
      onState: (state) => { if (state.event === "completed") this.move() }
    })
  }

  // Once. The player's `completed` and the clock can both arrive, and a second move while
  // the first is in flight would race two programmes into the same page.
  move() {
    if (this.moved) return
    this.moved = true
    clearTimeout(this.timer)

    const asked = this.dispatch("move", {
      target: document, cancelable: true, detail: { url: this.urlValue }
    })
    if (asked.defaultPrevented) return

    // Nothing answered. The page asks "did you mean to leave?" whenever the frame has
    // focus, which it has for most of a programme, so say this is deliberate first.
    window.leavingOnPurpose = true
    window.location.assign(this.urlValue)
  }
}
