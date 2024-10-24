import { Controller } from "@hotwired/stimulus";
import { Modal } from "bootstrap";

// Connects to data-controller="edit"
export default class extends Controller {
  static targets = ["modal"];

  connect() {
    // console.log("hello");
    this.modal = new Modal(this.modalTarget);
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

  close() {
    console.log('clicked');
    this.modalTarget.hide();
  }
}
