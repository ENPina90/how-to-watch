// app/javascript/controllers/poster_selector_controller.js
import { Controller } from "@hotwired/stimulus";
import * as bootstrap from "bootstrap";

export default class extends Controller {
  static targets = ["modal", "loading", "results", "error"];
  static values = {
    entryId: Number,
    imdb: String,
    seriesImdb: String,
    tmdb: String
  };

  connect() {
    // Listen for modal show event to load images
    this.modalTarget.addEventListener('show.bs.modal', () => {
      this.loadPosters();
    });
  }

  async loadPosters() {
    // Show loading, hide results and error
    this.loadingTarget.style.display = 'block';
    this.resultsTarget.style.display = 'none';
    this.errorTarget.style.display = 'none';

    try {
      const response = await fetch(`/entries/${this.entryIdValue}/fetch_posters`);
      const data = await response.json();

      if (data.posters && data.posters.length > 0) {
        this.displayPosters(data.posters);
      } else {
        this.showError();
      }
    } catch (error) {
      console.error('Error fetching posters:', error);
      this.showError();
    }
  }

  displayPosters(posters) {
    // Hide loading
    this.loadingTarget.style.display = 'none';
    this.resultsTarget.style.display = 'flex';

    // Clear previous results
    this.resultsTarget.innerHTML = '';

    // Display each poster
    posters.forEach((poster, index) => {
      const col = document.createElement('div');
      col.className = 'col-6 col-md-4 col-lg-3';

      col.innerHTML = `
        <div class="card h-100 poster-option" style="cursor: pointer;">
          <img src="${poster.url}" class="card-img-top" alt="Poster option ${index + 1}">
          <div class="card-body p-2">
            <small class="text-muted">${poster.source}</small>
          </div>
        </div>
      `;

      // Add click handler
      col.querySelector('.poster-option').addEventListener('click', () => {
        this.selectPoster(poster.url);
      });

      this.resultsTarget.appendChild(col);
    });
  }

  showError() {
    this.loadingTarget.style.display = 'none';
    this.resultsTarget.style.display = 'none';
    this.errorTarget.style.display = 'block';
  }

  async selectPoster(posterUrl) {
    try {
      const response = await fetch(`/entries/${this.entryIdValue}/update_poster`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({ poster_url: posterUrl })
      });

      if (response.ok) {
        // Close modal
        const modalInstance = bootstrap.Modal.getInstance(this.modalTarget);
        modalInstance.hide();

        // Reload page to show new poster
        window.location.reload();
      } else {
        alert('Failed to update poster. Please try again.');
      }
    } catch (error) {
      console.error('Error updating poster:', error);
      alert('Failed to update poster. Please try again.');
    }
  }
}
