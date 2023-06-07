import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="hover-play"
export default class extends Controller {
  static targets = ["poster"];

  connect() {}

  showPlay() {
    console.log(this.posterTarget);
  }
}
