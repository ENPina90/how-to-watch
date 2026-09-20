import { Controller } from "@hotwired/stimulus"

// Starts a player the app owns, for a provider it can serve itself.
//
// All this does is sequencing, and the sequence is the whole of it: the service worker in
// public/mega-sw.js has to be running before the element asks for a single byte, because
// the address it is pointed at exists nowhere else. The app does not serve `/mega/...`;
// the worker invents it. A request made a moment too early goes to the network, finds
// nothing, and the film is dead before it starts.
//
// So the address arrives as a data attribute and is handed over here, once the worker is
// not merely registered but in control of this page. Writing it into the element's `src`
// server-side would start the load during the parse, which races the worker and loses.
//
// Everything after that belongs to somebody else: player-progress records where you got
// to, player-keys drives it, the party bar keeps it in step. None of them need a case for
// this provider, because by the time they see it there is an ordinary <video> on the page.
export default class extends Controller {
  static values = {
    src: String,
    // Where to pick up, in seconds. The embeds take this in the URL; a player of our own
    // takes it by having its position set, which is also why it is applied on metadata
    // rather than now -- there is nothing to seek within until the length is known.
    start: Number,
  }

  async connect() {
    if (!this.hasSrcValue) return

    this.started = (event) => this.applyStart(event)
    this.element.addEventListener("loadedmetadata", this.started)

    if (!(await this.workerReady())) return

    this.element.src = this.srcValue
  }

  disconnect() {
    this.element.removeEventListener("loadedmetadata", this.started)
  }

  applyStart() {
    if (this.startValue > 0 && this.startValue < this.element.duration) {
      this.element.currentTime = this.startValue
    }
  }

  // Registered, activated, and controlling this page.
  //
  // The last of those is the one that catches people out. On a first visit the worker
  // installs and activates, and `navigator.serviceWorker.ready` resolves -- but the page
  // that registered it is not yet claimed, so its fetches still go past. The worker calls
  // clients.claim() on activation, and this waits for that to land.
  async workerReady() {
    if (!("serviceWorker" in navigator)) return this.giveUp("this browser has no service workers")

    try {
      await navigator.serviceWorker.register("/mega-sw.js")
      await navigator.serviceWorker.ready

      if (!navigator.serviceWorker.controller) {
        await new Promise((claimed) =>
          navigator.serviceWorker.addEventListener("controllerchange", claimed, { once: true }))
      }

      return true
    } catch (error) {
      return this.giveUp(error.message)
    }
  }

  // Nothing to fall back to, so the honest thing is to say so where the viewer is looking.
  // A <video> with no source shows a black rectangle and no reason for it, which is the
  // fault this app spent a fortnight chasing on somebody else's player.
  giveUp(reason) {
    this.dispatch("failed", { target: document, detail: { reason: reason } })

    // Built rather than written as markup. The reason is a browser's error message and not
    // ours to trust, and this page has a rule about rendering strings from elsewhere.
    const note = document.createElement("p")
    note.className = "cinema__player-failed"
    note.textContent = `This file cannot be played here (${reason}).`
    this.element.after(note)

    return false
  }
}
