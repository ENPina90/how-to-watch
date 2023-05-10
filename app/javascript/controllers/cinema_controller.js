import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="cinema"
export default class extends Controller {
  connect() {

  }

  fullscreen() {
    if (this.element.requestFullscreen) {
      this.element.requestFullscreen();
    } else if (this.element.webkitRequestFullscreen) {
      this.element.webkitRequestFullscreen();
    }
  }
}
