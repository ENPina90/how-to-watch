import { Controller } from "@hotwired/stimulus";

// The tab strip, the scroll-unlock caret and the Details/Notes panes on an entry card.
//
// Everything here is built in JavaScript on first hover and fetched on first open, and
// neither is premature. A channel page draws ~1,200 cards in one response:
// `spec/requests/list_show_payload_spec.rb` holds each card to a byte budget, and the
// margin left in it is about two hundred bytes -- less than a tab strip, never mind a cast
// list and a note per entry. Building on hover also keeps ~7,000 elements and 1,200 forced
// layouts off the initial render, since measuring whether the synopsis overflows costs a
// reflow apiece.
//
// So the card ships one `data-controller` and nothing else, and everything below appears
// for the handful of cards somebody actually points at.
export default class extends Controller {
  static targets = ["note", "status"];

  connect() {
    this.built = false;
    this.loaded = false;
    // The card rather than the details column, so this agrees with the `.grid-card:hover`
    // that reveals the strip -- bound to the column, moving down to the row of icons
    // counted as leaving and put the card back to its synopsis while the tabs were still
    // on screen.
    this.card = this.element.closest(".grid-card") || this.element;
    // Not a data-action: the attribute would ship on every card, and this listener is the
    // whole reason the controller is here.
    this.hovered = false;
    this.onEnter = () => { this.hovered = true; this.build(); };
    this.onLeave = () => { this.hovered = false; this.leave(); };
    this.card.addEventListener("mouseenter", this.onEnter);
    this.card.addEventListener("mouseleave", this.onLeave);
  }

  disconnect() {
    this.card.removeEventListener("mouseenter", this.onEnter);
    this.card.removeEventListener("mouseleave", this.onLeave);
  }

  // First hover only. The box everything here sits in is already in the card markup -- a
  // card has to be exactly the same shape before the pointer arrives as after it, and the
  // only way to be sure of that is for the layout not to change at all. This fills it.
  build() {
    if (this.built) return;
    this.built = true;

    this.wrapper = this.element.querySelector(".card-panes");
    this.plot = this.wrapper?.querySelector(".card-plot");
    if (!this.plot) return;

    this.pane = document.createElement("div");
    this.pane.className = "card-pane";
    this.pane.hidden = true;
    this.wrapper.appendChild(this.pane);

    this.tabs = document.createElement("div");
    this.tabs.className = "card-tabs";
    for (const [name, label] of [["synopsis", "Synopsis"], ["details", "Details"], ["notes", "Notes"]]) {
      const tab = document.createElement("button");
      tab.type = "button";
      tab.className = name === "synopsis" ? "card-tab card-tab--current" : "card-tab";
      tab.textContent = label;
      tab.addEventListener("click", () => this.show(name));
      this.tabs.appendChild(tab);
    }
    this.wrapper.insertBefore(this.tabs, this.plot);

    this.caret = document.createElement("button");
    this.caret.type = "button";
    this.caret.className = "card-scroll-toggle";
    this.caret.hidden = true;
    this.caret.setAttribute("aria-label", "Scroll this card");
    this.caret.innerHTML = '<i class="fa-solid fa-chevron-down"></i>';
    this.caret.addEventListener("click", () => this.toggleScroll());
    this.wrapper.appendChild(this.caret);

    this.current = "synopsis";
    this.refreshCaret();
  }

  // Which of the three is on screen. Synopsis is the plot the card already had; the other
  // two share one fetched pane, so switching between them costs nothing after the first.
  show(name) {
    if (this.current === name) return;

    this.lock();
    this.current = name;
    [...this.tabs.children].forEach((tab, i) => {
      tab.classList.toggle("card-tab--current", i === ["synopsis", "details", "notes"].indexOf(name));
    });

    // A class rather than `hidden`: the plot has to stay in the flow even when a pane is
    // over it, because it is what tells the auto-sized grid column how wide the details
    // column should be. Taken out, the column collapses to the width of the meta rows and
    // a gap opens between the poster and the text.
    this.plot.classList.toggle("card-plot--behind", name !== "synopsis");
    this.pane.hidden = name === "synopsis";
    // The fade says "there is more below" and belongs to flowing text. Over a box somebody
    // is about to type in it just looks like the bottom of the card has failed to paint.
    this.pane.classList.toggle("card-pane--notes", name === "notes");

    if (name === "synopsis") {
      this.refreshCaret();
      return;
    }

    this.load().then(() => {
      this.pane.querySelectorAll("[data-card-panes-pane]").forEach((section) => {
        section.hidden = section.dataset.cardPanesPane !== name;
      });
      this.refreshCaret();
    });
  }

  // One request for both panes, kept after it lands. A card whose note was just edited and
  // reopened should show what was typed, which it does: the textarea is the same element.
  load() {
    if (this.loaded) return Promise.resolve();
    this.loaded = true;

    return fetch(`/entries/${this.entryId}/panes`, { headers: { Accept: "text/html" } })
      .then((response) => (response.ok ? response.text() : Promise.reject(response.status)))
      .then((html) => {
        this.pane.innerHTML = html;
        const note = this.pane.querySelector("[data-card-panes-target='note']");
        if (note) {
          // On the way out rather than as you type: a note is a sentence somebody finishes,
          // and a request per keystroke is a request per keystroke.
          note.addEventListener("blur", () => {
            this.saveNote(note);
            // `leave` refuses to close a note that is being typed in, so a card whose box
            // still had focus when the pointer left stayed open on Notes -- and with the
            // strip only drawn on hover, that left a card sitting there showing a bare box
            // and no way to tell what it was. Finishing with the note outside the card
            // finishes the card.
            if (!this.hovered) this.show("synopsis");
          });
        }
      })
      .catch(() => {
        this.loaded = false;
        this.pane.innerHTML = '<p class="card-pane__empty">Could not load this. Try again.</p>';
      });
  }

  saveNote(note) {
    const value = note.value;
    if (value === this.savedNote) return;
    this.savedNote = value;

    fetch(`/entries/${this.entryId}/note`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      },
      body: JSON.stringify({ entry: { note: value } })
    })
      .then((response) => this.status(response.ok ? "Saved" : "Not saved"))
      .catch(() => this.status("Not saved"));
  }

  status(text) {
    const status = this.pane.querySelector("[data-card-panes-target='status']");
    if (!status) return;

    status.textContent = text;
    status.classList.add("is-shown");
    clearTimeout(this.statusTimer);
    this.statusTimer = setTimeout(() => status.classList.remove("is-shown"), 2000);
  }

  // The caret is only offered where there is something to scroll to, so a card whose
  // synopsis fits shows nothing -- which is most of them, and the reason this is measured
  // per pane rather than once.
  //
  // Never on Notes: the box there scrolls itself, being a textarea, and a caret promising
  // to unlock what is already unlocked is just a button that does nothing.
  refreshCaret() {
    const box = this.scrollable;
    this.caret.hidden = this.current === "notes" || !box || box.scrollHeight <= box.clientHeight + 4;
  }

  toggleScroll() {
    const box = this.scrollable;
    if (!box) return;

    const unlocked = box.classList.toggle(
      this.current === "synopsis" ? "card-plot--unlocked" : "card-pane--unlocked"
    );
    this.caret.classList.toggle("card-scroll-toggle--unlocked", unlocked);
  }

  // Leaving the card puts it back the way the page reads: locked, and showing its
  // synopsis. Locked, because a card you scrolled a minute ago must not still be eating
  // the wheel when you pass back over it on the way down the page -- that is the complaint
  // this whole thing exists to answer. Showing its synopsis, because the tabs go with the
  // pointer, and a card left on Details is a card stuck displaying a cast list with
  // nothing on screen to say why.
  //
  // Unless the note has focus: somebody typing who lets the pointer drift off the card is
  // still typing, and yanking the box away mid-sentence would lose what they wrote.
  leave() {
    this.lock();
    if (this.current === "notes" && this.pane.contains(document.activeElement)) return;

    this.show("synopsis");
  }

  lock() {
    if (!this.built || !this.plot) return;

    this.plot.classList.remove("card-plot--unlocked");
    this.pane.classList.remove("card-pane--unlocked");
    this.caret.classList.remove("card-scroll-toggle--unlocked");
  }

  // The card's own id, which the grid card already carries -- so the tabs cost the markup
  // one `data-controller` and not an id of their own.
  get entryId() {
    return this.element.closest(".grid-card")?.id;
  }

  get scrollable() {
    return this.current === "synopsis" ? this.plot : this.pane;
  }
}
