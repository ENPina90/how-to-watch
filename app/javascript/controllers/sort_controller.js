import { Controller } from "@hotwired/stimulus";
import Sortable from "sortablejs";

// Dragging rows in a channel's minimal view to reorder it.
//
// A row picked up on its own moves on its own. A ticked row carries every other ticked row
// with it: they land together where it is dropped, in the order they already had, and the
// rows after that point move down. Only where the page gives a move URL -- it does for
// somebody who may reorder the channel.
//
// Sortable drags one element, so the rest of the selection is not dragged along but closed
// up beside it on the drop; `sort--carrying` fades those rows for the length of the drag so
// it is clear they are coming too.
export default class extends Controller {
  static values = { moveUrl: String, direction: String };

  connect() {
    this.sortable = Sortable.create(this.element, {
      animation: 150,
      handle: ".fa-grip-vertical",
      onStart: this.pickUp.bind(this),
      onEnd: this.updatePosition.bind(this)
    });
  }

  disconnect() {
    if (this.sortable) this.sortable.destroy();
  }

  pickUp(event) {
    this.carrying = this.selectionFor(event.item);
    if (this.carrying.length > 1) this.element.classList.add("sort--carrying");
  }

  // Every ticked row in page order, if the row picked up is one of them.
  selectionFor(row) {
    if (!this.hasMoveUrlValue || !this.isTicked(row)) return [];

    return Array.from(this.element.children).filter((child) => this.isTicked(child));
  }

  isTicked(row) {
    const box = row.querySelector('[data-bulk-select-target="checkbox"]');
    return !!box && box.checked;
  }

  updatePosition(event) {
    this.element.classList.remove("sort--carrying");
    const carrying = this.carrying || [];
    this.carrying = null;

    if (carrying.length > 1) {
      this.moveSelection(event.item, carrying);
      return;
    }

    // Sortable's indexes are 0-based; positions start at 1.
    if (event.oldIndex === event.newIndex) return;

    this.renumber();
    this.send(`/entries/${event.item.dataset.id}/update_position`, { position: event.newIndex + 1 });
  }

  // Closes the selection up around the dropped row, then tells the server where it went.
  //
  // The place is sent as the entry just above it rather than as a number: the numbers on
  // this page count the channels mixed in among the entries, a search shows only some rows,
  // and a reversed sort runs backwards. The server reads "after this entry" in all three.
  moveSelection(dropped, rows) {
    let anchor = dropped.nextElementSibling;
    while (anchor && rows.includes(anchor)) anchor = anchor.nextElementSibling;
    rows.forEach((row) => this.element.insertBefore(row, anchor));

    // Channel rows carry no data-id and are not a place among the entries, so they are
    // stepped over.
    let previous = rows[0].previousElementSibling;
    while (previous && !previous.dataset.id) previous = previous.previousElementSibling;

    this.renumber();
    this.send(this.moveUrlValue, {
      entry_ids: rows.map((row) => row.dataset.id),
      after_id: previous ? previous.dataset.id : null,
      direction: this.directionValue
    });
  }

  // The numbers down the left are the page's own order, so they are redrawn to match it.
  renumber() {
    Array.from(this.element.children).forEach((row, index) => {
      const number = row.querySelector(".entry-minimal__index, .position-number");
      if (number) number.textContent = index + 1;
    });
  }

  // A refused or failed move reloads the page. The rows have already been moved on screen,
  // and leaving them in a place the channel does not have them is worse than the reload.
  send(url, body) {
    fetch(url, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').getAttribute("content")
      },
      body: JSON.stringify(body)
    })
      .then((response) => {
        if (!response.ok) throw new Error(`Reorder refused with ${response.status}`);
      })
      .catch((error) => {
        console.error("Error updating position:", error);
        window.location.reload();
      });
  }
}
