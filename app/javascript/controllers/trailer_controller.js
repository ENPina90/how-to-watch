// app/javascript/controllers/trailer_controller.js
import { Controller } from "@hotwired/stimulus";

// Drives the single shared trailer modal (shared/_trailer_modal). The card links are
// plain Bootstrap modal triggers, so the entry they belong to arrives as
// `event.relatedTarget` -- that is what lets one modal serve a whole list.
export default class extends Controller {
  static targets = ["iframe", "modal", "title"];

  connect() {
    this.modalTarget.addEventListener("show.bs.modal", this.load);
    this.modalTarget.addEventListener("hidden.bs.modal", this.unload);
  }

  disconnect() {
    this.modalTarget.removeEventListener("show.bs.modal", this.load);
    this.modalTarget.removeEventListener("hidden.bs.modal", this.unload);
  }

  load = (event) => {
    const trigger = event.relatedTarget;
    if (!trigger) return;

    this.iframeTarget.src = trigger.dataset.trailerUrl || "";
    this.titleTarget.textContent = trigger.dataset.trailerName
      ? `${trigger.dataset.trailerName} Trailer`
      : "Trailer";
  };

  // Stop playback on close. Without this the audio keeps going behind the backdrop.
  unload = () => {
    this.iframeTarget.src = "";
  };
}
