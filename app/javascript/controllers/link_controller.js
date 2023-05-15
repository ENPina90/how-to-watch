import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="completed"
export default class extends Controller {
  static values = { id: Number };

  connect() {
    // console.log(this.idValue)
  }

  toggle() {
    const url = `${window.location.origin}/entries/${this.idValue}/reportlink`;
    if (this.element.style.color === "red") {
      this.element.style.color = "grey";
    } else {
      this.element.style.color = "red";
    }
    fetch(url);
  }
}
