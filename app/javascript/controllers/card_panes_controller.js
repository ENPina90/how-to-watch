import { Controller } from "@hotwired/stimulus";

// The scroll-unlock caret on an entry card.
//
// The synopsis is clipped rather than scrollable, because a card that scrolls is a card
// that stops the page when the pointer crosses it. Where the text really is cut off, this
// offers a caret over the fade, and clicking it unlocks that one card.
//
// Everything here is built in JavaScript on first hover, which is not premature. A channel
// page draws ~1,200 cards in one response and `spec/requests/list_show_payload_spec.rb`
// holds each to a byte budget with about two hundred bytes of margin in it. Hover also
// keeps the measuring off the initial render: asking every card whether its synopsis
// overflows is a forced layout apiece.
//
// So the card ships one `data-controller` and nothing else.
export default class extends Controller {
  connect() {
    this.built = false;
    // The card rather than the details column, so this agrees with the `.grid-card:hover`
    // that reveals the caret.
    this.card = this.element.closest(".grid-card") || this.element;
    // Not a data-action: the attribute would ship on every card, and this listener is the
    // whole reason the controller is here.
    this.onEnter = () => this.build();
    this.onLeave = () => this.lock();
    this.card.addEventListener("mouseenter", this.onEnter);
    this.card.addEventListener("mouseleave", this.onLeave);
  }

  disconnect() {
    this.card.removeEventListener("mouseenter", this.onEnter);
    this.card.removeEventListener("mouseleave", this.onLeave);
  }

  // First hover only. Wraps the plot so the caret has something to be positioned against,
  // and leaves the plot itself otherwise untouched.
  build() {
    if (this.built) return;
    this.built = true;

    this.plot = this.element.querySelector(".card-plot");
    if (!this.plot) return;

    this.wrapper = document.createElement("div");
    this.wrapper.className = "card-panes";
    this.plot.parentNode.insertBefore(this.wrapper, this.plot);
    this.wrapper.appendChild(this.plot);

    this.caret = document.createElement("button");
    this.caret.type = "button";
    this.caret.className = "card-scroll-toggle";
    this.caret.hidden = true;
    this.caret.setAttribute("aria-label", "Scroll this card");
    this.caret.innerHTML = '<i class="fa-solid fa-chevron-down"></i>';
    this.caret.addEventListener("click", () => this.toggleScroll());
    this.wrapper.appendChild(this.caret);

    this.refreshCaret();
  }

  // Only offered where there is something to scroll to, so a card whose synopsis fits
  // shows nothing -- which is most of them.
  refreshCaret() {
    const box = this.plot;
    this.caret.hidden = !box || box.scrollHeight <= box.clientHeight + 4;
  }

  toggleScroll() {
    if (!this.plot) return;

    const unlocked = this.plot.classList.toggle("card-plot--unlocked");
    this.caret.classList.toggle("card-scroll-toggle--unlocked", unlocked);
  }

  // Re-locked when the pointer leaves, so a card you scrolled a minute ago is not still
  // eating the wheel when you pass back over it on the way down the page. That is the
  // complaint this whole thing exists to answer.
  lock() {
    if (!this.built || !this.plot) return;

    this.plot.classList.remove("card-plot--unlocked");
    this.caret.classList.remove("card-scroll-toggle--unlocked");
  }
}
