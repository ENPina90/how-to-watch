import { Controller } from "@hotwired/stimulus";

// Publishes the height of the page's sticky header row as `--section-header-top`, so a
// grouped list's section headings can park directly beneath it. The offset cannot live in
// the stylesheet: the row's height moves with the list title, the breadcrumb trail and the
// grouping menu.
export default class extends Controller {
  connect() {
    this.update = this.update.bind(this);
    // The row resizes without the window doing so -- a long title wrapping, a breadcrumb
    // trail appearing -- so watch the element itself rather than only the viewport.
    this.observer = new ResizeObserver(this.update);
    this.observer.observe(this.element);
    this.update();
  }

  disconnect() {
    this.observer.disconnect();
    document.documentElement.style.removeProperty("--section-header-top");
    document.documentElement.style.removeProperty("--title-bottom");
  }

  update() {
    // `top` is where this row parks itself (below the navbar); its own height is what
    // then sits between that and the first pixel a section heading may occupy.
    const parked = parseFloat(getComputedStyle(this.element).top) || 0;
    const row = this.element.getBoundingClientRect();
    // getBoundingClientRect, not offsetHeight: the row's height is routinely fractional
    // and offsetHeight rounds it away. Then round down and shed one more pixel, so the
    // heading overlaps the row rather than risking a gap below it -- a heading parked
    // even half a pixel low leaves the top border of the entry behind it showing
    // through, while the overlap is invisible against an opaque row stacked above.
    const offset = Math.floor(parked + row.height) - 1;

    document.documentElement.style.setProperty("--section-header-top", `${offset}px`);
    document.documentElement.style.setProperty("--title-bottom", `${this.titleBottom(parked, row)}px`);
  }

  // Where the channel's name ends, which is higher up than where the row does: the row
  // also holds the search box, the action icons and the grouping menu. Measured against
  // the row rather than the page, because the row is sticky and the page is not.
  titleBottom(parked, row) {
    const title = this.element.querySelector("h1");
    if (!title) return Math.floor(parked + row.height) - 1;

    return Math.ceil(parked + (title.getBoundingClientRect().bottom - row.top));
  }
}
