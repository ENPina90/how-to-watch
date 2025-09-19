import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    // Check if there's an 'added' parameter in the URL
    const urlParams = new URLSearchParams(window.location.search);
    const addedImdbId = urlParams.get('added');

    if (addedImdbId) {
      this.scrollToEntry(addedImdbId);
      // Clean up the URL by removing the parameter
      this.cleanUpUrl();
    }
  }

  scrollToEntry(imdbId) {
    // Look for an element with the IMDB ID
    setTimeout(() => {
      const entryElement = document.getElementById(imdbId) ||
                          document.querySelector(`[data-imdb="${imdbId}"]`) ||
                          document.querySelector(`[id*="${imdbId}"]`);

      if (entryElement) {
        entryElement.scrollIntoView({
          behavior: 'smooth',
          block: 'center'
        });

        // Add a temporary highlight effect
        entryElement.style.transition = 'background-color 0.5s ease';
        entryElement.style.backgroundColor = '#fff3cd';

        setTimeout(() => {
          entryElement.style.backgroundColor = '';
        }, 2000);
      }
    }, 500); // Small delay to ensure the page has loaded
  }

  cleanUpUrl() {
    // Remove the 'added' parameter from the URL without reloading the page
    const url = new URL(window.location);
    url.searchParams.delete('added');
    window.history.replaceState({}, document.title, url.pathname + url.search);
  }
}
