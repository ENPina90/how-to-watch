import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="letterboxd-check"
//
// Confirms a username is a real Letterboxd handle before the form is submitted, so the
// commonest mistake -- entering a display name -- is caught here rather than showing up
// later as a channel that silently never fills.
export default class extends Controller {
  static targets = ["username", "toggle", "status"];
  static values = { url: String };

  // Long enough not to fire a request per keystroke; short enough to feel immediate once
  // typing stops.
  static DEBOUNCE_MS = 500;

  connect() {
    this.check();
  }

  disconnect() {
    clearTimeout(this.timeout);
    this.controller?.abort();
  }

  // Typing: wait for a pause before asking.
  debouncedCheck() {
    clearTimeout(this.timeout);
    this.timeout = setTimeout(() => this.check(), this.constructor.DEBOUNCE_MS);
  }

  // Ticking the box: ask straight away, there is nothing to wait for.
  check() {
    clearTimeout(this.timeout);

    if (!this.hasStatusTarget) return;

    if (!this.enabled) {
      this.clear();
      return;
    }

    const username = this.usernameTarget.value.trim();
    if (!username) {
      this.render("pending", "Enter your Letterboxd username above.");
      return;
    }

    // A reply to a name the member has already typed past is worse than no reply, so any
    // request still in flight is dropped rather than allowed to land late.
    this.controller?.abort();
    this.controller = new AbortController();

    this.render("pending", "Checking Letterboxd…");

    fetch(`${this.urlValue}?username=${encodeURIComponent(username)}`, {
      headers: { Accept: "application/json" },
      signal: this.controller.signal,
    })
      .then((response) => {
        if (!response.ok) throw new Error(response.status);
        return response.json();
      })
      .then((data) => {
        const message = data.hint ? `${data.message} ${data.hint}` : data.message;
        this.render(data.status, message);
      })
      .catch((error) => {
        if (error.name === "AbortError") return;
        // The check is a convenience. If it cannot run, say so plainly rather than
        // implying the username is wrong -- the form still submits either way.
        this.render("pending", "Could not reach Letterboxd to check. You can still save.");
      });
  }

  get enabled() {
    return !this.hasToggleTarget || this.toggleTarget.checked;
  }

  clear() {
    this.statusTarget.textContent = "";
    this.statusTarget.className = "letterboxd-status";
    this.statusTarget.hidden = true;
  }

  render(status, message) {
    const icons = {
      ok: "fa-solid fa-circle-check",
      not_found: "fa-solid fa-triangle-exclamation",
      invalid: "fa-solid fa-triangle-exclamation",
      pending: "fa-solid fa-circle-notch fa-spin",
    };

    this.statusTarget.hidden = false;
    this.statusTarget.className = `letterboxd-status letterboxd-status--${status}`;
    this.statusTarget.replaceChildren(this.icon(icons[status]), document.createTextNode(` ${message}`));
  }

  icon(className) {
    const node = document.createElement("i");
    node.className = className;
    return node;
  }
}
