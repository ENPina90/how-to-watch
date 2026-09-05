import { Controller } from "@hotwired/stimulus"

// Moving between entries without rebuilding the page.
//
// The five ways out of an entry -- the channel above and below, the entry either side, and
// the shuffle -- used to be ordinary navigations, which meant the player was torn down and
// built again from nothing every time. That is the ~1.5s an embed takes to reach a moving
// picture (docs/guides/VIDSRC.md §6a), paid on every move.
//
// So the move happens in place instead. The server still renders the whole page and still
// records the position, exactly as before -- the difference is only that the answer is
// fetched and pasted in rather than navigated to. Three things change: the frame's src,
// the chrome that describes the entry, and the sidebar. The screen itself is untouched,
// which is what lets fullscreen survive a change of channel: fullscreen belongs to an
// element, and this leaves that element where it is.
//
// Everything is delegated from the screen rather than bound to the controls, because the
// controls are inside the chrome and are replaced by every move.
//
// Anything unexpected falls back to a real navigation. A channel with nothing in it
// redirects to its own page, a session can lapse, a fetch can fail -- none of those
// produce a player page to paste in, and all of them are somebody's ordinary business
// rather than an error worth reporting.
export default class extends Controller {
  static classes = ["moving"]

  connect() {
    this.clicked = (event) => this.linkClicked(event)
    this.submitted = (event) => this.formSubmitted(event)
    this.wentBack = () => this.historyMoved()

    this.element.addEventListener("click", this.clicked)
    this.element.addEventListener("submit", this.submitted)
    window.addEventListener("popstate", this.wentBack)
  }

  disconnect() {
    this.element.removeEventListener("click", this.clicked)
    this.element.removeEventListener("submit", this.submitted)
    window.removeEventListener("popstate", this.wentBack)
  }

  // Only the controls that say so. The channel name, the home button and anything else
  // that leaves the player behind are ordinary links and stay ordinary.
  linkClicked(event) {
    const link = event.target.closest("a[data-cinema-move]")
    if (!link || event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return

    event.preventDefault()
    this.moveTo(link.href)
  }

  // The three that record a position first are forms, not links, so they arrive here
  // instead. The form already carries its own `_method` and CSRF token; sending it whole
  // is what keeps this in step with whatever button_to generates.
  formSubmitted(event) {
    const form = event.target.closest("form[data-cinema-move]")
    if (!form) return

    event.preventDefault()
    this.moveTo(form.action, { method: "POST", body: new FormData(form) })
  }

  // The up-next card asking to advance. It offers rather than navigates, so that it still
  // works if this controller is not around to answer.
  moveFromEvent(event) {
    const { url, body } = event.detail
    event.preventDefault()
    this.moveTo(url, { method: "POST", body: body })
  }

  async moveTo(url, options = {}) {
    // A second press while the first is in flight would race two pages into the same DOM.
    if (this.moving) return
    this.moving = true
    this.element.classList.add(...this.movingClasses)

    // Where the player got to is worth keeping before the frame changes under it -- there
    // is no unload here to catch it later.
    this.dispatch("leaving", { target: document })

    try {
      const response = await fetch(url, { ...options, headers: { Accept: "text/html" }, redirect: "follow" })
      if (!response.ok) return this.giveUp(url)

      const page = new DOMParser().parseFromString(await response.text(), "text/html")
      // Not a player page: a channel with nothing to play, or a sign-in form.
      if (!page.getElementById("cinema-chrome")) return this.giveUp(response.url)

      this.apply(page, response.url)
    } catch {
      this.giveUp(url)
    } finally {
      this.moving = false
      this.element.classList.remove(...this.movingClasses)
    }
  }

  apply(page, url) {
    // The frame first. It is the slow part by an order of magnitude, and everything below
    // is instant, so it should not wait behind them.
    const frame = document.getElementById("cinema")
    const incoming = page.getElementById("cinema")
    if (frame && incoming && frame.src !== incoming.src) {
      // The title is what a screen reader calls the frame, so it has to move with the src
      // or the player is announced as whatever was playing before.
      frame.title = incoming.title
      frame.src = incoming.src
    }

    this.swap("cinema-chrome", page)
    this.swap("entriesSidebar", page)

    document.title = page.title
    history.pushState({}, "", url)
  }

  swap(id, page) {
    const current = document.getElementById(id)
    const incoming = page.getElementById(id)
    // Stimulus notices the replacement itself, so the controllers inside come back
    // connected to the new entry's values.
    if (current && incoming) current.replaceWith(incoming)
  }

  // The address bar was moved without a page load, so there is nothing in the document for
  // it to match. Letting the browser load it properly is both simplest and right.
  historyMoved() {
    window.leavingOnPurpose = true
    window.location.reload()
  }

  giveUp(url) {
    // The page asks "did you mean to leave?" whenever the frame has focus; this is the
    // page leaving deliberately.
    window.leavingOnPurpose = true
    window.location.assign(url)
  }
}
