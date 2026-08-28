import { Controller } from "@hotwired/stimulus";

// The channel's search is a magnifying glass until it is asked for. The field it opens is
// the same GET form as before -- this only decides when it takes up room.
export default class extends Controller {
  static targets = ["field"];

  connect() {
    // A query that is already filtering the page stays open: collapsing it would hide the
    // reason the channel looks the way it does.
    if (this.fieldTarget.value.trim()) this.element.classList.add("expanded");

    this.collapse = (event) => {
      if (this.element.contains(event.target)) return;
      // Not while it holds the query the page was filtered by.
      if (this.fieldTarget.value.trim()) return;

      this.element.classList.remove("expanded");
    };

    document.addEventListener("click", this.collapse);
  }

  disconnect() {
    document.removeEventListener("click", this.collapse);
  }

  open() {
    this.element.classList.add("expanded");
    this.fieldTarget.focus();
  }
}
