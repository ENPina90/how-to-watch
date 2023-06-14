import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="edit"
export default class extends Controller {
  static targets = ["modal"];

  connect() {
    // console.log("hello");
  }

  toggle(event) {
    const url = `${window.location.origin}/entries/${event.currentTarget.dataset.id}/edit`;
    console.log(url);
    fetch(url, { headers: { Accept: "text/plain" } })
      .then((response) => response.text())
      .then((data) => {
        this.modalTarget.innerHTML = data;
        // console.log(data);
      });
  }
}
