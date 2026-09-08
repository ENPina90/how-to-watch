import { Controller } from "@hotwired/stimulus";

// Brings the row you are actually on into view when the player page opens.
//
// Both sidebars can run to hundreds of rows -- a channel list of thirty-odd, an episode
// list of a hundred and more -- and both open at the top, which is nowhere near what is
// playing.
//
// The waiting is the hard part. On the player page both sidebars start collapsed, so at
// connect there is no box to scroll: a height of zero, and a row with no position in it.
// Scrolling then does nothing at all, and the sidebar opens at the top as if none of this
// were here. So it measures when it can, and otherwise waits for the panel to be given a
// size.
//
// Once only. Reopening a sidebar you have since scrolled by hand should leave it where you
// left it.
export default class extends Controller {
  static targets = ["active"];

  connect() {
    if (!this.hasActiveTarget) return;
    if (this.reveal()) return;

    this.observer = new ResizeObserver(() => {
      if (this.reveal()) this.stopWatching();
    });
    this.observer.observe(this.element);
  }

  disconnect() {
    this.stopWatching();
  }

  stopWatching() {
    this.observer?.disconnect();
    this.observer = null;
  }

  // True once it has actually scrolled, false while there is nothing to scroll yet.
  reveal() {
    if (!this.hasActiveTarget || this.element.clientHeight === 0) return false;

    const container = this.element.getBoundingClientRect();
    const row = this.activeTarget.getBoundingClientRect();
    // Centred, so there is context above and below rather than the row pinned to an edge.
    const offset = row.top - container.top - (container.height / 2 - row.height / 2);

    // Scrolling this rather than calling scrollIntoView, which would also scroll the page
    // and any other ancestor that happens to overflow.
    this.element.scrollTop += offset;

    return true;
  }
}
