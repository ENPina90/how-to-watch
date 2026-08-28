import { Controller } from "@hotwired/stimulus";

// Votes arrive from phones in the room, so the board on the screen refetches itself while
// a round is open. It asks for the page it is already on and lifts the board out of it --
// no second endpoint to keep in step with the one that renders this.
export default class extends Controller {
  static targets = ["board"];
  static values = { url: String, interval: { type: Number, default: 5000 } };

  connect() {
    this.timer = setInterval(() => this.refresh(), this.intervalValue);
  }

  disconnect() {
    clearInterval(this.timer);
  }

  refresh() {
    // A tab left open in the background is not a room watching a screen.
    if (document.hidden) return;

    fetch(this.urlValue, { headers: { Accept: "text/html" } })
      .then((response) => (response.ok ? response.text() : null))
      .then((html) => {
        if (!html) return;

        const board = new DOMParser()
          .parseFromString(html, "text/html")
          .querySelector('[data-vote-board-target="board"]');

        // Gone means the round has closed and the page is showing a result instead.
        if (!board) return window.location.reload();
        // Only when something changed, so a click is never interrupted mid-press.
        if (board.innerHTML.trim() !== this.boardTarget.innerHTML.trim()) {
          this.boardTarget.innerHTML = board.innerHTML;
        }
      })
      .catch((error) => console.error("Could not refresh the vote board:", error));
  }
}
