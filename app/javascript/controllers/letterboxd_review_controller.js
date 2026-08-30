import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="letterboxd-review"
//
// Opening the review prompt happens on Letterboxd, so the app only finds out about the
// review when it next reads the diary. This tells the server a review is probably coming,
// so it can book a refresh for once the feed has caught up.
export default class extends Controller {
  static values = { url: String };

  // Does not preventDefault: the link still opens Letterboxd in its new tab. keepalive
  // lets the request outlive this page if the click navigates it.
  ping() {
    fetch(this.urlValue, {
      method: "POST",
      keepalive: true,
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
      },
      // The refresh is a nicety; the weekly run catches anything this misses.
    }).catch(() => {});
  }
}
