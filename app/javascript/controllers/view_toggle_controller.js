import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["icon"]
  static values = { url: String }

  toggleView() {
    const currentView = new URLSearchParams(window.location.search).get('view') || 'full';
    const newView = currentView === 'minimal' ? 'full' : 'minimal';

    if (newView === 'minimal') {
      this.iconTarget.classList.remove('fa-down-left-and-up-right-to-center');
      this.iconTarget.classList.add('fa-up-right-and-down-left-from-center');
    } else {
      this.iconTarget.classList.remove('fa-up-right-and-down-left-from-center');
      this.iconTarget.classList.add('fa-down-left-and-up-right-to-center');
    }

    const url = new URL(window.location);
    url.searchParams.set('view', newView);
    window.history.pushState({}, '', url);

    fetch(`${this.urlValue}?view=${newView}`, {
      headers: { 'Accept': 'text/plain' }
    })
      .then(response => response.text())
      .then(html => {
        document.getElementById('entries-container').innerHTML = html;
      })
      .catch(error => {
        console.error('Error fetching entries partial:', error);
      });
  }
}
