import { Controller } from "@hotwired/stimulus";
import Sortable from "sortablejs";

// Drag-to-reorder for the cable dial on /admin/cable.
//
// Sends the whole order rather than "this one moved to index N", the same bargain
// source-sort makes: there are a handful of channels, so the saving is not worth having,
// and sending the lot lets the server renumber 1..N and repair a gap or a collision as a
// side effect of any drag.
export default class extends Controller {
  static values = { url: String };

  connect() {
    this.sortable = Sortable.create(this.element, {
      animation: 150,
      handle: ".cable-dial__grip",
      ghostClass: "cable-dial__row--dragging",
      onEnd: () => this.persist(),
    });
  }

  disconnect() {
    this.sortable?.destroy();
  }

  async persist() {
    // Renumbered before the request rather than after it: the order on screen is already
    // the new one, so the numbers beside it should agree immediately instead of after a
    // round trip. They are channel numbers -- the thing the guide's gutter and the banner's
    // badge show -- so a row sitting third under a "2" is the one misleading state here.
    this.renumber();

    const ids = this.rows.map((row) => row.dataset.channelId);

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        },
        body: JSON.stringify({ ids }),
      });

      if (!response.ok) throw new Error(`HTTP ${response.status}`);
    } catch (error) {
      // The drag stands on screen but the server did not take it, so the next load would
      // silently undo it -- and on this page that means the dial everybody else is watching
      // is not the one shown here. Say so rather than let the two disagree quietly.
      console.error("Could not save the channel order:", error);
      this.element.classList.add("cable-dial--unsaved");
    }
  }

  get rows() {
    return Array.from(this.element.querySelectorAll("[data-channel-id]"));
  }

  renumber() {
    this.rows.forEach((row, index) => {
      const label = row.querySelector(".cable-dial__number");
      if (label) label.textContent = index + 1;
    });
  }
}
