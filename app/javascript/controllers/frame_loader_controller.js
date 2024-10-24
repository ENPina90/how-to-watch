import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Check if the frame is loading dynamically or if it already has content
    if (!this.element.hasAttribute('complete')) {
      // If no content is pre-rendered, hide the frame until fully loaded
      this.element.classList.add("invisible");

      // Add event listener to show the frame once it's loaded
      this.element.addEventListener("turbo:frame-load", () => {
        this.element.classList.remove("invisible");
        this.element.setAttribute('complete', true); // Mark as complete
      });
    }
  }
}
