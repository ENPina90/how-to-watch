// app/javascript/controllers/trailer_controller.js
import { Controller } from "@hotwired/stimulus";
import * as bootstrap from "bootstrap";

export default class extends Controller {
  static targets = ["iframe", "modal"];

  connect() {
    // Controller is connected
  }

  show(event) {
    event.preventDefault();
    const trailerUrl = event.currentTarget.dataset.trailerUrl;

    // Set the iframe's src using the target provided by Stimulus
    this.iframeTarget.src = trailerUrl;

    // Initialize and show the modal
    if (!this.modalInstance) {
      this.modalInstance = new bootstrap.Modal(this.modalTarget);
      // Ensure the hide method is called when the modal is closed
      this.modalTarget.addEventListener("hidden.bs.modal", () => this.hide());
    }
    this.modalInstance.show();
  }

  hide() {
    this.iframeTarget.src = "";
  }
}
