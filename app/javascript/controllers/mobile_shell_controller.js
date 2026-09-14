import { Controller } from "@hotwired/stimulus"
import Mustache from "mustachejs"
import TmdbService from "services/tmdb_service"
import { TmdbSearchBehavior } from "services/tmdb_search_behavior"

// The bar at the top of every page in the phone view, and everything that hangs off it.
//
// The field searches everything there is, and what a result offers depends on where the
// search was made from:
//
//   on a channel, one button that puts it on that channel -- there is nothing to choose
//   between, you are already looking at where it goes;
//
//   on the home page, a heart that files it in the member's favourites straight away, and a
//   + that opens the picker to choose one of their own channels for it.
//
// Told whether to search at all by `mode`, and where to add by `listId`, rather than
// deciding for itself from what is on the page: guessing would make the field's job depend
// on markup somewhere else.
const DEBOUNCE = 350

export default class MobileShellController extends Controller {
  static targets = [
    "input", "menu", "overlay", "results", "movieType", "showType", "result",
    "picker", "pickerName", "pickerInput", "pickerChannel", "pickerNoMatches"
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

  // A search costs two round trips to somebody else's API, so it waits for a pause in the
  // typing.
  typed() {
    clearTimeout(this.debounce)
    if (this.modeValue !== "search") return

    this.debounce = setTimeout(() => this.search(), DEBOUNCE)
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
    this.closePicker()
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

  // `picker` chooses which buttons the card carries: with no channel behind the search,
  // the heart and the + that opens the picker; on a channel, the one that adds to it.
  render(results, label, type) {
    const picker = !(this.listIdValue > 0)

    this.resultsTarget.innerHTML = Mustache.render(this.template.innerHTML, {
      results: results.map((result) => ({ ...result, addLabel: label, addType: type, picker }))
    })
  }

  showErrorMessage() {
    this.resultsTarget.innerHTML = '<p class="m-overlay__state">Nothing found.</p>'
  }

  flip(event) {
    event.currentTarget.closest(".m-card")?.classList.toggle("m-card--flipped")
  }

  // ---- adding ---------------------------------------------------------------------

  // Straight onto the channel this search was made from.
  add(event) {
    const button = event.currentTarget
    if (button.disabled || !(this.listIdValue > 0)) return

    const body = this.importBody(button)
    if (button.dataset.type) body.append("type", button.dataset.type)

    // The same endpoint the full site posts to, which answers with a turbo stream meant for
    // a channel page this one is not. The reply is not applied: what the button says is the
    // whole of the feedback, and the channel behind the overlay is re-read when it is next
    // opened.
    this.adding(button, "Adding…", "Added",
      this.post(`/lists/${this.listIdValue}/entries`, body, "text/vnd.turbo-stream.html"))
  }

  // Into the member's favourites, without asking which channel that is: it is the one
  // they already said.
  favourite(event) {
    const button = event.currentTarget
    if (button.disabled) return

    this.adding(button, '<i class="fa-solid fa-spinner fa-spin"></i>', '<i class="fa-solid fa-heart"></i>',
      this.post("/lists/add_to_favorites", this.importBody(button)))
  }

  // ---- the picker -----------------------------------------------------------------
  //
  // A page of its own over the results rather than a menu off the button: the member's
  // channels can run to dozens, and a dropdown that long is one you scroll the wrong thing
  // inside. The + that opened it is remembered, because it is what carries the ids and
  // what is marked done afterwards.

  pick(event) {
    this.picking = event.currentTarget
    if (!this.hasPickerTarget) return

    this.pickerNameTarget.textContent = this.picking.dataset.title
    this.pickerInputTarget.value = ""
    this.filterPicker()
    this.pickerTarget.hidden = false
  }

  closePicker() {
    this.picking = null
    if (this.hasPickerTarget) this.pickerTarget.hidden = true
  }

  // Local, and deliberately so: the rows are already here.
  filterPicker() {
    const needle = this.pickerInputTarget.value.trim().toLowerCase()
    let shown = 0

    this.pickerChannelTargets.forEach((channel) => {
      const matches = !needle || channel.dataset.name.includes(needle)

      channel.hidden = !matches
      if (matches) shown += 1
    })

    this.pickerNoMatchesTarget.hidden = shown > 0
  }

  // The picker closes on success and stays open on a refusal, so the row that shook is
  // still there to try again or to pick another instead.
  addToChannel(event) {
    const row = event.currentTarget
    const plus = this.picking
    if (!plus || row.disabled) return

    const body = this.importBody(plus)
    body.append("list_id", row.dataset.listId)

    row.disabled = true
    row.classList.add("m-channel--busy")

    this.post("/lists/add_to_list", body)
      .then(() => {
        const count = row.querySelector(".m-channel__count")
        if (count) count.textContent = Number(count.textContent) + 1

        plus.classList.add("m-add--done")
        this.closePicker()
      })
      .catch(() => {
        row.classList.add("m-channel--refused")
        setTimeout(() => row.classList.remove("m-channel--refused"), 1500)
      })
      .finally(() => {
        row.disabled = false
        row.classList.remove("m-channel--busy")
      })
  }

  // ---- the requests ---------------------------------------------------------------

  importBody(button) {
    const body = new FormData()
    body.append("imdb", button.dataset.imdbId)
    body.append("tmdb", button.dataset.tmdbId)
    return body
  }

  post(url, body, accept = "application/json") {
    return fetch(url, {
      method: "POST",
      body: body,
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        Accept: accept
      }
    }).then((response) => {
      if (!response.ok) throw new Error("Failed to add")
    })
  }

  // A button that says it is working, then that it worked -- or goes back to what it said
  // and shakes. Importing a series fetches every episode, so the wait can be long enough to
  // need saying.
  adding(button, busy, done, request) {
    const original = button.innerHTML
    button.disabled = true
    button.innerHTML = busy

    request
      .then(() => {
        button.innerHTML = done
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
