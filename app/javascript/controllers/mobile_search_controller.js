import { Controller } from "@hotwired/stimulus";
import Mustache from "mustachejs";
import * as bootstrap from "bootstrap";
import TmdbService from "services/tmdb_service";
import { TmdbSearchBehavior } from "services/tmdb_search_behavior";

class MobileSearchController extends Controller {
  static targets = ["input", "results", "typeButtons", "resultsContent"];
  static values = {
    userLists: Array,
    apiKey: String,
    currentListId: String
  };

  connect() {
    this.api = 'https://api.themoviedb.org/3/'
    this.apiKey = this.apiKeyValue.length ? this.apiKeyValue : document.querySelector('meta[name="tmdb-key"]')?.content
    this.tmdbService = new TmdbService(this.apiKey);
    this.movieTemplate = document.querySelector("#mobileSearchMovieTemplate");
    this.showTemplate = document.querySelector("#mobileSearchShowTemplate");
    this.currentSearchType = 'movie'; // Default to movie search
  }

  // -----------------------------
  // SEARCH METHODS
  // -----------------------------

  // Method called when search type radio buttons are clicked
  switchToMovieSearch() {
    this.currentSearchType = 'movie';
    this.performSearch();
  }

  switchToShowSearch() {
    this.currentSearchType = 'show';
    this.performSearch();
  }

  // Universal search method that delegates based on current search type
  performSearch() {
    const keyword = this.inputTarget.value.trim();
    if (keyword.length < 2) {
      this.hideResults();
      return;
    }

    // Show overlay with buttons immediately when user starts typing
    this.showOverlay();

    if (this.currentSearchType === 'movie') {
      this.tmdbSearch();
    } else if (this.currentSearchType === 'show') {
      this.tmdbShow();
    }
  }

  // -----------------------------
  // RENDERING METHODS
  // -----------------------------

  renderMovies(movies) {
    const movieData = { movies };
    const output = Mustache.render(this.movieTemplate.innerHTML, movieData);
    this.showResultsOverlay(output);
  }

  renderShows(shows) {
    const showData = { movies: shows };
    const output = Mustache.render(this.showTemplate.innerHTML, showData);
    this.showResultsOverlay(output);
  }

  showResultsOverlay(html) {
    if (this.hasResultsContentTarget) {
      this.resultsContentTarget.innerHTML = html;
    } else {
      this.resultsTarget.innerHTML = html;
    }
    this.resultsTarget.classList.remove('d-none');

    // Add click outside to close
    document.addEventListener('click', this.handleClickOutside.bind(this), { once: true });
  }

  // -----------------------------
  // LIST SELECTION MODAL METHODS
  // -----------------------------

  showListSelectionModal(event) {
    event.preventDefault();
    const button = event.currentTarget;

    // Store the selected movie/show data
    this.selectedItem = {
      imdbID: button.dataset.imdbId,
      tmdbID: button.dataset.tmdbId,
      title: button.dataset.title,
      poster: button.dataset.poster
    };

    // Check if we're in a list show view (currentListId is present)
    if (this.currentListIdValue) {
      // Add directly to the current list
      this.addToCurrentList(event);
      return;
    }

    // Otherwise, show the list selection modal
    // Update modal content
    document.getElementById('mobileModalMovieTitle').textContent = this.selectedItem.title;
    document.getElementById('mobileModalMovieYear').textContent = this.selectedItem.year || '';

    // Populate list options
    this.populateListOptions();

    // Show the modal
    const modal = new bootstrap.Modal(document.getElementById('mobileListSelectionModal'));
    modal.show();
  }

  addToCurrentList(event) {
    event.preventDefault();
    const button = event.currentTarget;

    // Show loading state
    const originalText = button.innerHTML;
    button.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Adding...';
    button.disabled = true;

    // Create form data
    const formData = new FormData();
    formData.append('imdb', this.selectedItem.imdbID);
    formData.append('tmdb', this.selectedItem.tmdbID);
    formData.append('list_id', this.currentListIdValue);

    // Submit to the add to list endpoint
    fetch('/lists/add_to_list', {
      method: 'POST',
      body: formData,
      headers: {
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content'),
        'Accept': 'application/json'
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        this.showSuccessMessage(this.selectedItem.title, 'this list');
        // Hide search results
        this.hideResults();
        this.inputTarget.value = '';
        // Reload the page to show the new entry
        window.location.reload();
      } else {
        throw new Error(data.error || 'Failed to add to list');
      }
    })
    .catch(error => {
      console.error('Error adding to list:', error);
      this.showAddErrorToast(this.selectedItem.title);
      // Reset button
      button.innerHTML = originalText;
      button.disabled = false;
    });
  }

  populateListOptions() {
    const container = document.getElementById('mobileListSelectionContainer');
    container.innerHTML = '';

    // Get user lists from the data attribute
    const userLists = this.userListsValue || [];

    if (userLists.length === 0) {
      container.innerHTML = '<p class="text-muted text-center">No lists available</p>';
      return;
    }

    // Create list option buttons
    userLists.forEach(list => {
      const listOption = document.createElement('button');
      listOption.className = 'mobile-list-option';
      listOption.textContent = `${list.name} (${list.entries_count} entries)`;
      listOption.dataset.listId = list.id;
      listOption.addEventListener('click', (e) => this.addToList(e, list.id, list.name));
      container.appendChild(listOption);
    });
  }

  addToList(event, listId, listName) {
    event.preventDefault();

    // Show loading state on the clicked button
    const button = event.currentTarget;
    const originalText = button.textContent;
    button.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Adding...';
    button.disabled = true;

    // Create form data
    const formData = new FormData();
    formData.append('imdb', this.selectedItem.imdbID);
    formData.append('tmdb', this.selectedItem.tmdbID);
    formData.append('list_id', listId);

    // Submit to the add to list endpoint
    fetch('/lists/add_to_list', {
      method: 'POST',
      body: formData,
      headers: {
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content'),
        'Accept': 'application/json'
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        this.showSuccessMessage(this.selectedItem.title, listName);
        // Close modal
        const modal = bootstrap.Modal.getInstance(document.getElementById('mobileListSelectionModal'));
        modal.hide();
        // Hide search results
        this.hideResults();
        this.inputTarget.value = '';
      } else {
        throw new Error(data.error || 'Failed to add to list');
      }
    })
    .catch(error => {
      console.error('Error adding to list:', error);
      this.showAddErrorToast(this.selectedItem.title);
      // Reset button
      button.textContent = originalText;
      button.disabled = false;
    });
  }

  showSuccessMessage(title, listName) {
    // Create and show a toast notification
    const toastHtml = `
      <div class="toast align-items-center text-white bg-success border-0" role="alert" aria-live="assertive" aria-atomic="true">
        <div class="d-flex">
          <div class="toast-body">
            Successfully added "${title}" to ${listName}!
          </div>
          <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
        </div>
      </div>
    `;

    this.showToast(toastHtml);
  }

  showAddErrorToast(title) {
    const toastHtml = `
      <div class="toast align-items-center text-white bg-danger border-0" role="alert" aria-live="assertive" aria-atomic="true">
        <div class="d-flex">
          <div class="toast-body">
            Failed to add "${title}" to favorites. Please try again.
          </div>
          <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
        </div>
      </div>
    `;

    this.showToast(toastHtml);
  }

  // Override error display methods
  showErrorMessage() {
    const errorHtml = '<div class="text-center text-muted">No results found</div>';
    if (this.hasResultsContentTarget) {
      this.resultsContentTarget.innerHTML = errorHtml;
    } else {
      this.resultsTarget.innerHTML = '<div class="p-3">' + errorHtml + '</div>';
    }
    this.resultsTarget.classList.remove('d-none');
  }
}

// The search/render pipeline these two controllers share, defined once.
Object.assign(MobileSearchController.prototype, TmdbSearchBehavior);

export default MobileSearchController;
