import { Controller } from "@hotwired/stimulus";

// Collapses one section of a grouped list. The heading stays put -- only the entries
// under it are hidden -- so a collapsed section still reads as a section, and still
// parks under the header row on the way past.
export default class extends Controller {
  static targets = ["body"];

  toggle(event) {
    const heading = event.currentTarget;
    const collapsing = heading.getAttribute("aria-expanded") !== "false";

    heading.setAttribute("aria-expanded", String(!collapsing));
    this.bodyTarget.hidden = collapsing;
  }
}
