import { Controller } from "@hotwired/stimulus";

// The three ways an entry can be given a picture, shown one at a time.
//
// They are genuinely three different things, which is why the form used to spell all three
// out at once and why that read as a wall: `pic` points at somebody else's host for as long
// as it stays up -- the broken-poster audit exists to find out when it stops -- while the
// other two keep a copy of their own, one fetched from a link and one uploaded.
//
// Only the tabs are switched here. Which one *wins* if more than one is filled in is
// settled on the server, and deliberately: an uploaded file beats a fetched link, because
// the duplicate form opens with the original's poster already in the link field and an
// upload is the more explicit of the two. So nothing is cleared when you change tab --
// switching away from something you typed and back again finds it still there.
export default class extends Controller {
  static targets = ["tab", "panel"];
  static values = { current: String };

  connect() {
    this.choose(this.currentValue || this.tabTargets[0]?.dataset.posterInputKeyParam);
  }

  // The click handler. Stimulus hands the tab's `data-poster-input-key-param` over in
  // `event.params`, so the key lives on the button that means it.
  select(event) {
    this.choose(event.params.key);
  }

  choose(key) {
    if (!key) return;

    this.currentValue = key;
    this.tabTargets.forEach((tab) => {
      tab.classList.toggle("poster-tab--current", tab.dataset.posterInputKeyParam === key);
      tab.setAttribute("aria-selected", tab.dataset.posterInputKeyParam === key);
    });
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.posterInputPanel !== key;
    });
  }
}
