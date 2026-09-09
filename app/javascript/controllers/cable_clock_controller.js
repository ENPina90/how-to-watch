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
// How long before a change to start warming what comes after it. The embed behind it takes
// about a second and a half to reach a picture, so this is mostly slack -- but a warmed
// frame is also a buffered one, and arriving with a few seconds already in hand is the
// difference between the next programme starting and the next programme loading.
const WARM_LEAD = 45000

export default class extends Controller {
  static values = {
    // The channel's own path. Asked again when the programme ends, and it answers with
    // whatever is on by then -- so a tab left open overnight catches up in one request
    // rather than stepping through everything it slept through.
    url: String,
    // When this channel next shows something different, from the server, in UTC. Not always
    // the end of the slot: a programme with a commercial break after it changes twice, once
    // into the adverts and once out of them. The client's clock may be wrong; what matters
    // is that it is wrong by the same amount for the whole page.
    endsAt: String,
    // Where to go when the film ends before the clock says it should -- the same channel,
    // asked to cut to the adverts. Absent through the break itself, when there is nothing
    // after the adverts but the next programme.
    fillerUrl: String,
    // When this programme started, in UTC. Used to work out where the schedule thinks the
    // film should be, so that a file shorter than the catalogue claims can be spotted.
    programmeStartsAt: String,
    adapter: String,
    frame: String,
    // What the catalogue claims this programme runs to, in seconds, and where to say
    // otherwise. Zero means it claims nothing, which is the case worth reporting: the
    // schedule is guessing, and the player is the only thing that knows.
    runtime: Number,
    runtimeUrl: String,
    token: String
  }

  connect() {
    this.scheduleMove()
    this.watchPlayer()
  }

  disconnect() {
    clearTimeout(this.timer)
    clearTimeout(this.warmTimer)
    this.player?.destroy()
  }

  scheduleMove() {
    const endsAt = Date.parse(this.endsAtValue)
    if (Number.isNaN(endsAt)) return

    // Ask for the next programme to be warmed shortly before it is due. Unlike the watch
    // page there is no up-next card to take the hint from, so the clock gives it.
    const lead = Math.max(endsAt - Date.now() - WARM_LEAD, 0)
    this.warmTimer = setTimeout(() => this.dispatch("warm", { target: document }), lead)

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

    this.startedAt = Date.parse(this.programmeStartsAtValue)

    this.player = playerAdapterFor(this.adapterValue, iframe, {
      onState: (state) => this.playerReported(state)
    })
  }

  playerReported(state) {
    this.learnRuntime(state)

    if (state.event === "completed") return this.move({ early: true })
    if (this.overrunning(state)) return this.move({ early: true })
  }

  // Tell the server how long the file really is, where the catalogue does not say.
  //
  // A schedule built on a guess is wrong in one of two ways, and both are visible: a guess
  // that is short cuts the programme off partway through, and one that is long leaves the
  // slot running after the film has ended. Neither can be seen from the server -- only the
  // player knows what it is holding.
  //
  // Once per page, and only where there is a gap to fill. It does not fix the programme
  // being watched, whose slot was laid out yesterday; it fixes every one after it.
  learnRuntime({ duration }) {
    if (this.told || !duration || duration <= 0) return
    if (this.runtimeValue > 0 || !this.runtimeUrlValue) return

    this.told = true

    const body = new FormData()
    body.append("_method", "patch")
    body.append("seconds", Math.round(duration))
    body.append("authenticity_token", this.tokenValue)

    // Nothing on the page waits on this, and a correction that does not arrive is simply a
    // schedule that stays as wrong as it was.
    fetch(this.runtimeUrlValue, { method: "POST", body: body }).catch(() => {})
  }

  // Is the schedule asking for a point this file does not have?
  //
  // The catalogue's runtime is a claim rather than a measurement: it is missing for a fair
  // number of entries -- which get a guess -- and merely wrong for others, and the provider
  // may hold a different cut in any case. Handed a start position past the end, the player
  // does not refuse and does not stop: it quietly starts from the beginning and plays the
  // film again, which is how this showed up. Measured 2026-09-09 against a 1354s episode
  // asked to start at 99999.
  //
  // The player is the only thing that knows the real length, and it says so in every
  // report. Where the schedule wants to be past that, the programme is over.
  overrunning({ duration }) {
    if (!duration || duration <= 0 || Number.isNaN(this.startedAt)) return false

    return (Date.now() - this.startedAt) / 1000 >= duration
  }

  // Once. The player's `completed` and the clock can both arrive, and a second move while
  // the first is in flight would race two programmes into the same page.
  //
  // A film that ends early cuts to the adverts rather than to the next programme: the
  // schedule has not moved, and sitting on a finished player until it catches up is the one
  // thing a channel never does. Where there is no break to cut to, this is the ordinary
  // move it always was.
  move({ early = false } = {}) {
    if (this.moved) return
    this.moved = true
    clearTimeout(this.timer)
    clearTimeout(this.warmTimer)

    const url = (early && this.fillerUrlValue) || this.urlValue
    const asked = this.dispatch("move", {
      target: document, cancelable: true, detail: { url: url }
    })
    if (asked.defaultPrevented) return

    // Nothing answered. The page asks "did you mean to leave?" whenever the frame has
    // focus, which it has for most of a programme, so say this is deliberate first.
    window.leavingOnPurpose = true
    window.location.assign(url)
  }
}
