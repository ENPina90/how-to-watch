import { Controller } from "@hotwired/stimulus";

// "Add to Channel" outside the navbar's search overlay -- on the watch_now page, where the
// same modal should open for whatever is playing. list-search owns that modal and lives on
// the navbar, so a button elsewhere on the page has no controller of that identity above
// it to bind an action to. It listens on the document for this event instead, which is
// the same path the search results take once the modal is open.
export default class extends Controller {
  static values = { imdb: String, tmdb: String, title: String, poster: String };

  open(event) {
    event.preventDefault();

    document.dispatchEvent(new CustomEvent("openListModal", {
      detail: {
        imdbID: this.imdbValue,
        tmdbID: this.tmdbValue,
        title: this.titleValue,
        poster: this.posterValue
      }
    }));
  }
}
