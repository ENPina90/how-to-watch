import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="completed"
export default class extends Controller {
  static values = { id: Number }

  // Completion is a write, so the route is PATCH and the token is required.
  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  connect() {
    // console.log(this.idValue)
  }

  toggle() {
    // Temporarily disable auto-advance, just use original behavior
    this.originalToggle()
  }

  originalToggle() {
    const url = `${window.location.origin}/entries/${this.idValue}/complete`

    fetch(url, {
      method: 'PATCH',
      headers: {
        'Accept': 'text/vnd.turbo-stream.html, text/html',
        'X-Requested-With': 'XMLHttpRequest',
        'X-Turbo-Frame': 'true',
        'X-CSRF-Token': this.csrfToken()
      }
    }).then(response => {
      if (response.ok) {
        const contentType = response.headers.get('content-type')
        if (contentType && contentType.includes('turbo-stream')) {
          return response.text()
        } else {
          // If it's HTML, just toggle the classes manually
          this.element.classList.toggle("fa-solid")
          this.element.classList.toggle("fa-regular")
          return null
        }
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
