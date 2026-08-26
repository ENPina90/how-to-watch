import { Controller } from "@hotwired/stimulus";

const PARAM = "section";

// The section list in the left rail filters the entries rather than jumping to an anchor.
// Nothing is fetched and nothing re-renders: every section is already on the page, so a
// click is a `hidden` flag on the sections that are out. Several sections can be on at
// once, an empty selection means no filter, and the choice is written to the URL so a
// reload or a shared link comes back to the same view.
export default class extends Controller {
  static targets = ["option", "section"];

  connect() {
    this.selected = new Set(this.selectionFromUrl());
    this.apply();
  }

  toggle(event) {
    const key = event.currentTarget.dataset.section;

    if (this.selected.has(key)) {
      this.selected.delete(key);
    } else {
      this.selected.add(key);
    }

    this.apply();
    this.writeUrl();
  }

  apply() {
    // An empty selection is "no filter", not "nothing matches".
    const filtering = this.selected.size > 0;

    this.sectionTargets.forEach((section) => {
      section.hidden = filtering && !this.selected.has(section.dataset.section);
    });

    this.optionTargets.forEach((option) => {
      option.setAttribute("aria-pressed", String(this.selected.has(option.dataset.section)));
    });
  }

  selectionFromUrl() {
    // Only keys this page actually renders: the grouping in the menu above may have
    // changed since the link was made, and its sections are named differently.
    const known = new Set(this.optionTargets.map((option) => option.dataset.section));

    return new URLSearchParams(window.location.search).getAll(PARAM).filter((key) => known.has(key));
  }

  writeUrl() {
    const url = new URL(window.location);

    // One repeated param rather than one joined value: section names are free text --
    // genres, month names -- and there is no separator they are guaranteed not to hold.
    url.searchParams.delete(PARAM);
    this.selected.forEach((key) => url.searchParams.append(PARAM, key));

    // replaceState, not pushState: this is a view of the page you are on, not a new one
    // to walk back through one click at a time.
    window.history.replaceState({}, "", url);
  }
}
