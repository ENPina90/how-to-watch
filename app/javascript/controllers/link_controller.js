import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="link"
export default class extends Controller {
  static values = { id: Number };

  connect() {
    // console.log(this.idValue)
  }

  toggle() {
    const url = `${window.location.origin}/entries/${this.idValue}/reportlink`;
    // State lives in the class, not an inline style -- the style attribute was rendered
    // once per card and read back here, which meant the colour had to ship with every
    // entry for this toggle to know which way to go.
    const broken = this.element.classList.toggle("link-broken");
    this.element.classList.toggle("link-ok", !broken);
    fetch(url, {
      method: 'PATCH',
      headers: { 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content }
    });
  }
}
