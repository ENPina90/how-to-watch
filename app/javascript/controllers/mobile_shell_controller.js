import { Controller } from "@hotwired/stimulus"
import Mustache from "mustachejs"
import TmdbService from "services/tmdb_service"
import { TmdbSearchBehavior } from "services/tmdb_search_behavior"

// The bar at the top of every page in the phone view, and everything that hangs off it.
//
// One field, doing one of two jobs depending on which page it is on:
//
//   on the home page it filters the channels already on screen, which is a local question
//   about a short list and has no business being a round trip;
//
//   on a channel it searches everything there is and offers to put a result on that
//   channel, which is the whole reason this half of the app exists.
//
// Told which by `mode`, rather than deciding for itself from what is on the page: the two
// behaviours read the same keystrokes and guessing between them would make the field's job
// depend on markup somewhere else.
const DEBOUNCE = 350

export default class MobileShellController extends Controller {
  static targets = [
    "input", "menu", "overlay", "results", "movieType", "showType",
    "channels", "channel", "noMatches", "result"
  ]
  static values = { mode: String, listId: Number }

  connect() {
    this.tmdbService = new TmdbService(document.querySelector('meta[name="tmdb-key"]')?.content)
    this.template = document.querySelector("#mobileResultTemplate")
    this.currentSearchType = "movie"
    this.dismiss = (event) => this.closeMenuOnOutsideClick(event)
    document.addEventListener("click", this.dismiss)
  }

  disconnect() {
    document.removeEventListener("click", this.dismiss)
    clearTimeout(this.debounce)
  }

  // ---- the menu -------------------------------------------------------------------

  toggleMenu(event) {
    event.stopPropagation()
    this.menuTarget.hidden = !this.menuTarget.hidden
  }

  closeMenuOnOutsideClick(event) {
    if (this.hasMenuTarget && !this.menuTarget.hidden && !this.element.contains(event.target)) {
      this.menuTarget.hidden = true
    }
  }

  // ---- the field ------------------------------------------------------------------

  typed() {
    clearTimeout(this.debounce)

    if (this.modeValue === "filter") return this.filterChannels()

    // A search costs two round trips to somebody else's API, so it waits for a pause in
    // the typing. The filter does not -- it is a loop over a dozen rows already on screen.
    this.debounce = setTimeout(() => this.search(), DEBOUNCE)
  }

  // Local, and deliberately so: the rows are already here and the list is a dozen long.
  filterChannels() {
    const needle = this.inputTarget.value.trim().toLowerCase()
    let shown = 0

    this.channelTargets.forEach((channel) => {
      const matches = !needle || channel.dataset.name.includes(needle)

      channel.hidden = !matches
      if (matches) shown += 1
    })

    if (this.hasNoMatchesTarget) this.noMatchesTarget.hidden = shown > 0
  }

  // ---- searching ------------------------------------------------------------------

  search() {
    const keyword = this.inputTarget.value.trim()

    if (keyword.length < 2) return this.closeOverlay()

    this.overlayTarget.hidden = false
    this.currentSearchType === "show" ? this.tmdbShow() : this.tmdbSearch()
  }

  searchMovies() {
    this.currentSearchType = "movie"
    this.markType()
    this.search()
  }

  searchShows() {
    this.currentSearchType = "show"
    this.markType()
    this.search()
  }

  markType() {
    const show = this.currentSearchType === "show"

    this.movieTypeTarget.classList.toggle("m-overlay__type--on", !show)
    this.showTypeTarget.classList.toggle("m-overlay__type--on", show)
  }

  closeOverlay() {
    this.overlayTarget.hidden = true
    this.resultsTarget.innerHTML = ""
  }

  // ---- what the shared search behaviour calls back ----------------------------------
  //
  // tmdbSearch and tmdbShow are the navbar's, mixed in below. They expect a controller with
  // a results target and these three methods, and they write the loading state themselves.

  renderMovies(movies) {
    this.render(movies, "Movie", "movie")
  }

  renderShows(shows) {
    this.render(shows, "Series", this.currentSearchType === "anime" ? "anime" : "show")
  }

  render(results, label, type) {
    this.resultsTarget.innerHTML = Mustache.render(this.template.innerHTML, {
      results: results.map((result) => ({ ...result, addLabel: label, addType: type }))
    })
  }

  showErrorMessage() {
    this.resultsTarget.innerHTML = '<p class="m-overlay__state">Nothing found.</p>'
  }

  // ---- adding ---------------------------------------------------------------------

  flip(event) {
    event.currentTarget.closest(".m-card")?.classList.toggle("m-card--flipped")
  }

  // Straight onto the channel this search was made from -- there is no picker, because
  // there is nothing to pick between: on a phone you are on a channel or you are on the
  // home page, and the home page's field does not search.
  add(event) {
    const button = event.currentTarget
    if (button.disabled || !(this.listIdValue > 0)) return

    const original = button.innerHTML
    button.disabled = true
    button.innerHTML = "Adding…"

    const body = new FormData()
    body.append("imdb", button.dataset.imdbId)
    body.append("tmdb", button.dataset.tmdbId)
    if (button.dataset.type) body.append("type", button.dataset.type)

    fetch(`/lists/${this.listIdValue}/entries`, {
      method: "POST",
      body: body,
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        // The same endpoint the full site posts to, which answers with a turbo stream
        // meant for a channel page this one is not. The reply is not applied: what the
        // button says is the whole of the feedback, and the channel behind the overlay is
        // re-read when it is next opened.
        Accept: "text/vnd.turbo-stream.html"
      }
    })
      .then((response) => {
        if (!response.ok) throw new Error("Failed to add")

        button.innerHTML = "Added"
        button.classList.add("m-add--done")
      })
      .catch(() => {
        button.innerHTML = original
        button.disabled = false
        button.classList.add("m-add--refused")
        setTimeout(() => button.classList.remove("m-add--refused"), 1500)
      })
  }
}

// The navbar's search, unchanged and not copied: tmdbSearch and tmdbShow run as methods of
// this controller, so their `this.inputTarget` and `this.tmdbService` are the ones above.
// Same mixin the other two search controllers use.
Object.assign(MobileShellController.prototype, TmdbSearchBehavior)
