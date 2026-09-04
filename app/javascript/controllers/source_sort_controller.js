import { Controller } from "@hotwired/stimulus";
import Sortable from "sortablejs";

// Drag-to-reorder for the provider list on /sources.
//
// Sends the whole order rather than "this one moved to index N". There are a handful of
// providers, so the saving is not worth having, and the positions in this table have
// collided before -- sending the lot lets the server renumber 1..N and repair that as a
// side effect of any drag.
export default class extends Controller {
  static values = { url: String };

  connect() {
    this.sortable = Sortable.create(this.element, {
      animation: 150,
      handle: ".source-card__grip",
      ghostClass: "source-card--dragging",
      onEnd: () => this.persist(),
    });
  }

  disconnect() {
    this.sortable?.destroy();
  }

  async persist() {
    // Renumbered before the request rather than after it: the order on screen is already
    // the new one, so the labels should agree immediately instead of after a round trip.
    this.renumber();

    const ids = this.cards.map((card) => card.dataset.sourceId);

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
      // silently undo it. Say so rather than let the two disagree quietly.
      console.error("Could not save the provider order:", error);
      this.element.classList.add("source-cards--unsaved");
    }
  }

  get cards() {
    return Array.from(this.element.querySelectorAll("[data-source-id]"));
  }

  renumber() {
    this.cards.forEach((card, index) => {
      const label = card.querySelector(".source-card__rank");
      if (label) label.textContent = `Source ${index + 1}`;
    });
  }
}
