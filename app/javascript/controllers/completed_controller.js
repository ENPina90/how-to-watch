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

    // Don't toggle classes immediately - let the server response handle it
    fetch(url, {
      method: 'GET',
      headers: {
        'Accept': 'text/vnd.turbo-stream.html',
        'X-Requested-With': 'XMLHttpRequest'
      }
    }).then(response => {
      if (response.ok) {
        return response.text()
      }
    }).then(html => {
      if (html) {
        // Process the turbo stream response
        Turbo.renderStreamMessage(html)
      }
    }).catch(error => {
      console.error('Error toggling completion:', error)
      // Fallback: toggle classes manually
      this.element.classList.toggle("fa-solid")
      this.element.classList.toggle("fa-regular")
    })
  }

}
