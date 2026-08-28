import { Controller } from "@hotwired/stimulus";

const PICKS = 3;

// "Up Next" suggests something to watch, so it offers only what is actually in play: the
// entries the section filter has left on the page, minus everything this user has already
// watched. The pool is read out of the DOM rather than fetched -- the filter never goes to
// the server, so the page itself is the only thing that knows what is in range.
export default class extends Controller {
  static targets = ["picks", "pick", "empty"];

  connect() {
    // An ordered list names its own next entry instead of suggesting any, so there is no
    // box to fill and no pool to watch.
    if (!this.hasPicksTarget) return;

    this.onFilterChanged = (event) => {
      // Changing the filter is a change of range, and the suggestions are meant to be
      // for what you have selected -- so it re-picks. Restoring the selection this page
      // loaded with is not a change, and keeps the picks that are still in range.
      if (event.detail?.restoring) this.reconcile(); else this.upnext();
    };
    // A completion redraw takes one entry out of the pool rather than changing its shape,
    // so it tops up instead of reshuffling what is next to it.
    this.reconcileAfterRender = () => requestAnimationFrame(() => this.reconcile());
    this.listening = true;

    document.addEventListener("section-filter:changed", this.onFilterChanged);
    document.addEventListener("turbo:before-stream-render", this.reconcileAfterRender);

    this.picks = this.renderedPicks();
    this.reconcile();
  }

  disconnect() {
    if (!this.listening) return;

    document.removeEventListener("section-filter:changed", this.onFilterChanged);
    document.removeEventListener("turbo:before-stream-render", this.reconcileAfterRender);
  }

  // The refresh icon, and every change of filter: a fresh set drawn from what is in range.
  // Bound as an action, so it takes no arguments.
  upnext() {
    this.picks = this.sample(this.eligible(), PICKS);
    this.paint();
  }

  // Keep the picks that still qualify and fill the gaps, for a pool that lost one entry
  // rather than changing shape -- marking something watched should not reshuffle the two
  // suggestions next to it.
  reconcile() {
    const eligible = this.eligible();
    const kept = this.picks.filter((card) => eligible.includes(card));
    const spare = eligible.filter((card) => !kept.includes(card));

    this.picks = kept.concat(this.sample(spare, PICKS - kept.length));
    this.paint();
  }

  // A pick is a place on this page, not a page of its own, so the click never navigates.
  // Scrolling by hand also clears the header row and the section heading parked under it,
  // which an anchor jump lands behind -- it puts the card's top edge at the very top of
  // the viewport, where both of those are sitting.
  scrollTo(event) {
    const link = event.target.closest("a[href^='#']");
    const card = link && document.getElementById(link.getAttribute("href").slice(1));
    if (!card) return;

    event.preventDefault();

    const parked = parseFloat(
      getComputedStyle(document.documentElement).getPropertyValue("--section-header-top")
    ) || 0;
    // Measured rather than assumed: the heading is only there in a grouped view, and its
    // height moves with the font.
    const heading = card.closest(".entry-section")?.querySelector("h3");
    const offset = parked + (heading?.offsetHeight ?? 0);

    window.scrollTo({
      top: card.getBoundingClientRect().top + window.scrollY - offset,
      behavior: "smooth"
    });
  }

  eligible() {
    return Array.from(document.querySelectorAll(".grid-card")).filter((card) => {
      // Whatever is on the page: a filtered-out section and a collapsed one are both
      // `hidden`, and a pick scrolls to its card, which cannot work for a card that is
      // not showing.
      if (card.closest("[hidden]")) return false;

      // The signal a card already carries: a hollow eye is unwatched, a solid one is
      // watched. Nothing extra has to be stamped on every card to read it.
      return card.querySelector(".completion-status .fa-regular.fa-eye") !== null;
    });
  }

  // The links the server rendered, mapped back to their cards, so a page that needs no
  // adjusting keeps the selection it arrived with instead of reshuffling on load.
  renderedPicks() {
    const eligible = new Set(this.eligible());

    return Array.from(this.picksTarget.querySelectorAll("a"))
      .map((link) => document.getElementById(link.getAttribute("href").slice(1)))
      .filter((card) => eligible.has(card));
  }

  paint() {
    this.picksTarget.replaceChildren();

    this.picks.forEach((card) => {
      const link = document.createElement("a");
      // A card is keyed by its entry id, and a pick scrolls to it.
      link.href = `#${card.id}`;
      link.className = "channel-sidebar__item";
      link.textContent = this.title(card);
      this.picksTarget.append(link);
    });

    // Nothing to offer is a real state: a filter can select sections this user has
    // finished, and a fully watched list has nothing left at all.
    const empty = this.picks.length === 0;
    if (this.hasEmptyTarget) this.emptyTarget.hidden = !empty;
    if (!this.hasPickTarget) return;

    // Pick for me goes straight to the player, so it needs the card's watch link rather
    // than its anchor. Assigning an undefined href would resolve against the current URL
    // and send the click to /lists/undefined, so an unusable pick hides the link instead.
    const url = empty ? null : this.watchUrl(this.sample(this.picks, 1)[0]);
    this.pickTarget.hidden = !url;
    if (url) this.pickTarget.href = url;
  }

  sample(cards, count) {
    if (count <= 0) return [];

    // Copied first: sorting in place would shuffle the caller's array as a side effect.
    return [...cards].sort(() => 0.5 - Math.random()).slice(0, count);
  }

  watchUrl(card) {
    // Every card type wraps its poster in the watch link; none of them put a class on it.
    return card.querySelector(".card-picture a")?.href;
  }

  title(card) {
    return card.querySelector(".card-header")?.textContent.trim();
  }
}
