import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="completed"
export default class extends Controller {
  static values = { id: Number }

  connect() {
    // console.log(this.idValue)
  }

  toggle() {
    const url = `${window.location.origin}/entries/${this.idValue}/complete`
    console.log(url);
    this.element.classList.toggle("fa-solid")
    this.element.classList.toggle("fa-regular")
    fetch(url)
  }
}
