import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="completed"
export default class extends Controller {
  static values = { id: Number }

  connect() {
    // console.log(this.idValue)
  }

  toggle() {
    // Temporarily disable auto-advance, just use original behavior
    this.originalToggle()
  }

  markCompleteAndShowModal() {
    const completeUrl = `${window.location.origin}/entries/${this.idValue}/complete`

    fetch(completeUrl, {
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
        // Process the turbo stream response to update the icon
        Turbo.renderStreamMessage(html)

        // Show the auto-advance modal
        const modalElement = document.getElementById('autoAdvanceModal')
        console.log('Modal element:', modalElement)

        if (modalElement) {
          const modal = new bootstrap.Modal(modalElement)
          modal.show()
          console.log('Modal shown')
        } else {
          console.error('Modal element not found')
        }
      }
    }).catch(error => {
      console.error('Error marking complete:', error)
      // Fallback to original behavior
      this.originalToggle()
    })
  }

  originalToggle() {
    const url = `${window.location.origin}/entries/${this.idValue}/complete`

    fetch(url, {
      method: 'GET',
      headers: {
        'Accept': 'text/vnd.turbo-stream.html, text/html',
        'X-Requested-With': 'XMLHttpRequest',
        'X-Turbo-Frame': 'true'
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
