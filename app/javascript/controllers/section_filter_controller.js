import { Controller } from "@hotwired/stimulus";

const PARAM = "section";

// The section list in the left rail filters the entries rather than jumping to an anchor.
// Nothing is fetched and nothing re-renders: every section is already on the page, so a
// click is a `hidden` flag on the sections that are out. Several sections can be on at
// once -- one at a time, or by dragging down the rail to take a run of them -- an empty
// selection means no filter, and the choice is written to the URL so a reload or a shared
// link comes back to the same view.
export default class extends Controller {
  static targets = ["option", "section"];

  connect() {
    this.selected = new Set(this.selectionFromUrl());
    this.apply({ restoring: true });
  }

  // Keyboard activation only. A click from a mouse or a touch reports the click count in
  // `detail`; one from Enter or Space reports 0, and the pointer handlers below have
  // already dealt with everything else.
  toggle(event) {
    if (event.detail !== 0) return;

    const key = event.currentTarget.dataset.section;
    this.set(key, !this.selected.has(key));
    this.commit();
  }

  // Pressing a section starts a drag, whether or not one follows: the press itself is the
  // first selection, and every section the pointer then crosses is set the same way. What
  // that press does to the section it lands on -- select or deselect -- is what the rest
  // of the run does too, so dragging back over a section does not undo it halfway.
  start(event) {
    if (event.button !== 0) return;

    const key = event.currentTarget.dataset.section;
    this.dragValue = !this.selected.has(key);
    this.set(key, this.dragValue);
    this.paint();

    // Touch and pen capture the pointer to the element it went down on, which would keep
    // pointerenter from firing on the sections it then crosses.
    event.currentTarget.releasePointerCapture?.(event.pointerId);
    // And without this a touch drag scrolls the page instead of running the selection.
    event.preventDefault();

    this.finish = () => {
      this.dragValue = undefined;
      // Once for the run rather than once per section: this is what re-picks Up Next and
      // rewrites the URL, and neither wants doing at every step of a drag.
      this.commit();
    };
    window.addEventListener("pointerup", this.finish, { once: true });
    window.addEventListener("pointercancel", this.finish, { once: true });
  }

  // Crossing a section mid-drag.
  extend(event) {
    if (this.dragValue === undefined) return;

    this.set(event.currentTarget.dataset.section, this.dragValue);
    this.paint();
  }

  disconnect() {
    window.removeEventListener("pointerup", this.finish);
    window.removeEventListener("pointercancel", this.finish);
  }

  set(key, on) {
    if (on) this.selected.add(key); else this.selected.delete(key);
  }

  apply({ restoring = false } = {}) {
    this.paint();

    // Up Next offers what is in range, and nothing re-renders here for it to notice on
    // its own. On document because it listens from inside this element, not above it.
    // `restoring` marks the selection this page loaded with, as opposed to a click.
    this.dispatch("changed", { target: document, detail: { restoring } });
  }

  commit() {
    this.apply();
    this.writeUrl();
  }

  // The selection made visible. Cheap enough to run at every step of a drag: one pass
  // over the sections, whatever is behind them.
  paint() {
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
