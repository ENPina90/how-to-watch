import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="link"
export default class extends Controller {
  static values = { id: Number };

  async toggle() {
    // State lives in the class, not an inline style -- the style attribute was rendered
    // once per card and read back here, which meant the colour had to ship with every
    // entry for this toggle to know which way to go.
    const broken = !this.element.classList.contains("link-broken");
    this.show(broken);

    // The state wanted, not "flip it": a double click then sets the same thing twice.
    const url = `${window.location.origin}/entries/${this.idValue}/reportlink?broken=${broken}`;
    try {
      const response = await fetch(url, {
        method: "PATCH",
        headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content }
      });
      // A refusal (not your channel) comes back as a 403, and the icon must not go on
      // claiming a report that was never saved.
      if (!response.ok) this.show(!broken);
    } catch {
      this.show(!broken);
    }
  }

  show(broken) {
    this.element.classList.toggle("link-broken", broken);
    this.element.classList.toggle("link-ok", !broken);
  }
}
