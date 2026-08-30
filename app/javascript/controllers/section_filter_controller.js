import { Controller } from "@hotwired/stimulus";

const PARAM = "section";
// The second axis: which channel an entry came from. A page that borrows entries from the
// channels inside it groups them all together, and this is the only thing left that says
// where each one lives.
const SOURCE_PARAM = "source";

// The section list in the left rail filters the entries rather than jumping to an anchor.
// Nothing is fetched and nothing re-renders: every section is already on the page, so a
// click is a `hidden` flag on the sections that are out. Several sections can be on at
// once -- one at a time, or by dragging down the rail to take a run of them -- an empty
// selection means no filter, and the choice is written to the URL so a reload or a shared
// link comes back to the same view.
export default class extends Controller {
  static targets = ["option", "section", "source", "card"];

  connect() {
    this.selected = new Set(this.selectionFromUrl(PARAM, this.optionTargets, "section"));
    this.sources = new Set(this.selectionFromUrl(SOURCE_PARAM, this.sourceTargets, "source"));
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

  // The source toggles. No drag on these: there are a handful of channels rather than forty
  // decades, and a run of them is not a thing anyone reaches for.
  toggleSource(event) {
    const id = event.currentTarget.dataset.source;

    if (this.sources.has(id)) this.sources.delete(id); else this.sources.add(id);
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
    // An empty selection on either axis is "no filter", not "nothing matches". The two are
    // ANDed: the seventies *and* from School Night In.
    const bySection = this.selected.size > 0;
    const bySource = this.sources.size > 0;

    this.cardTargets.forEach((card) => {
      card.hidden = bySource && !this.sources.has(card.dataset.source);
    });

    this.sectionTargets.forEach((section) => {
      const wrongSection = bySection && !this.selected.has(section.dataset.section);
      // A section whose every card was hidden by the source axis is a heading over
      // nothing, so it goes too.
      section.hidden = wrongSection || this.emptied(section);
    });

    this.optionTargets.forEach((option) => {
      option.setAttribute("aria-pressed", String(this.selected.has(option.dataset.section)));
    });

    this.sourceTargets.forEach((source) => {
      source.setAttribute("aria-pressed", String(this.sources.has(source.dataset.source)));
    });
  }

  emptied(section) {
    const cards = section.querySelectorAll('[data-section-filter-target="card"]');

    return cards.length > 0 && Array.from(cards).every((card) => card.hidden);
  }

  selectionFromUrl(param, buttons, attribute) {
    // Only keys this page actually renders: the grouping in the menu above may have
    // changed since the link was made, and its sections are named differently.
    const known = new Set(buttons.map((button) => button.dataset[attribute]));

    return new URLSearchParams(window.location.search).getAll(param).filter((key) => known.has(key));
  }

  writeUrl() {
    const url = new URL(window.location);

    // One repeated param rather than one joined value: section names are free text --
    // genres, month names -- and there is no separator they are guaranteed not to hold.
    url.searchParams.delete(PARAM);
    this.selected.forEach((key) => url.searchParams.append(PARAM, key));
    url.searchParams.delete(SOURCE_PARAM);
    this.sources.forEach((id) => url.searchParams.append(SOURCE_PARAM, id));

    // replaceState, not pushState: this is a view of the page you are on, not a new one
    // to walk back through one click at a time.
    window.history.replaceState({}, "", url);
  }
}
