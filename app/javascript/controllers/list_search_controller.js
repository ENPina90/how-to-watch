import { Controller } from "@hotwired/stimulus";
import Mustache from "mustachejs";
import * as bootstrap from "bootstrap";
import TmdbService from "services/tmdb_service";
import { TmdbSearchBehavior } from "services/tmdb_search_behavior";

class ListSearchController extends Controller {
  static targets = ["input", "results", "typeButtons", "resultsContent"];
  static values = {
    userLists: Array,
    apiKey: String
  };

  connect() {
    this.api = 'https://api.themoviedb.org/3/'
    this.apiKey = this.apiKeyValue.length ? this.apiKeyValue : document.querySelector('meta[name="tmdb-key"]')?.content
    this.tmdbService = new TmdbService(this.apiKey);
    this.movieTemplate = document.querySelector("#listSearchMovieTemplate");
    this.showTemplate = document.querySelector("#listSearchShowTemplate");
    this.listTemplate = document.querySelector("#listSearchListTemplate");
    this.selectedMovie = null;
    this.currentSearchType = 'movie'; // Default to movie search

    // Listen for global modal open events
    this.boundHandleGlobalModal = this.handleGlobalModalOpen.bind(this);
    document.addEventListener('openListModal', this.boundHandleGlobalModal);
  }

  disconnect() {
    // Clean up event listener
    document.removeEventListener('openListModal', this.boundHandleGlobalModal);
  }

  handleGlobalModalOpen(event) {
    console.log('handleGlobalModalOpen called with:', event.detail);
    this.selectedMovie = event.detail;
    this.updateModalContent();

    const modalElement = document.getElementById('listSelectionModal');
    if (modalElement) {
      console.log('Modal element found, showing modal');
      const modal = new bootstrap.Modal(modalElement);
      modal.show();
    } else {
      console.error('Modal element not found');
    }
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

  switchToAnimeSearch() {
    this.currentSearchType = 'anime';
    this.performSearch();
  }

  switchToListSearch() {
    this.currentSearchType = 'list';
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
    } else if (this.currentSearchType === 'anime') {
      this.tmdbShow(); // Anime uses same search as shows
    } else if (this.currentSearchType === 'list') {
      this.searchLists();
    }
  }

  // -----------------------------
  // RENDERING METHODS
  // -----------------------------

  // -----------------------------
  // MODAL METHODS
  // -----------------------------

  openListModal(event) {
    event.preventDefault();
    const button = event.currentTarget;

    // Store the selected movie data
    this.selectedMovie = {
      imdbID: button.dataset.imdbId,
      tmdbID: button.dataset.tmdbId,
      title: button.dataset.title,
      poster: button.dataset.poster
    };

    // Update modal content
    this.updateModalContent();

    // Show the modal
    const modalElement = document.getElementById('listSelectionModal');
    if (!modalElement) {
      console.error('Modal element not found');
      return;
    }

    const modal = new bootstrap.Modal(modalElement);
    modal.show();
  }

  updateModalContent() {
    if (!this.selectedMovie) return;

    const modalTitle = document.querySelector('#listSelectionModalLabel');
    const modalPoster = document.querySelector('#modalMoviePoster');
    const listContainer = document.querySelector('#listSelectionContainer');

    modalTitle.textContent = `Add "${this.selectedMovie.title}" to a list`;
    modalPoster.src = this.selectedMovie.poster;
    modalPoster.alt = this.selectedMovie.title;

    // Check if user has any lists
    if (this.userListsValue.length === 0) {
      listContainer.innerHTML = `
        <div class="text-center">
          <p class="text-muted mb-3">You don't have any lists yet!</p>
          <a href="/lists/new" class="btn btn-primary">Create Your First List</a>
        </div>
      `;
      return;
    }

    // Generate list options
    const listsHtml = this.userListsValue.map(list => `
      <div class="list-option mb-2">
        <button type="button"
                class="btn btn-outline-primary w-100 d-flex justify-content-between align-items-center"
                data-action="click->list-search#addToList"
                data-list-id="${list.id}"
                data-list-name="${list.name}">
          <span>${list.name}</span>
          <small class="text-muted">${list.entries_count || 0} entries</small>
        </button>
      </div>
    `).join('');

    listContainer.innerHTML = listsHtml;
  }

  addToList(event) {
    console.log('addToList called');
    console.log('selectedMovie:', this.selectedMovie);

    if (!this.selectedMovie) {
      console.error('No selected movie');
      return;
    }

    const button = event.currentTarget;
    const listId = button.dataset.listId;
    const listName = button.dataset.listName;

    console.log('Adding to list:', listId, listName);

    // Show loading state
    button.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Adding...';
    button.disabled = true;

    // Create form data
    const formData = new FormData();
    formData.append('imdb', this.selectedMovie.imdbID);
    formData.append('tmdb', this.selectedMovie.tmdbID);

    // Submit to the entries controller
    fetch(`/lists/${listId}/entries`, {
      method: 'POST',
      body: formData,
      headers: {
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content'),
        'Accept': 'application/json'
      }
    })
    .then(response => {
      if (response.ok) {
        // Success - redirect to the list with anchor to newly added entry
        window.location.href = `/lists/${listId}?added=${this.selectedMovie.imdbID}`;
      } else {
        throw new Error('Failed to add entry');
      }
    })
    .catch(error => {
      console.error('Error adding to list:', error);
      this.showErrorMessage();
      // Reset button
      button.innerHTML = `<span>${listName}</span><small class="text-muted">${button.dataset.entriesCount || 0} entries</small>`;
      button.disabled = false;
    });
  }

  closeModal() {
    const modalElement = document.getElementById('listSelectionModal');
    if (!modalElement) {
      console.error('Modal element not found');
      this.selectedMovie = null;
      return;
    }

    const modal = bootstrap.Modal.getInstance(modalElement);
    if (modal) {
      modal.hide();
    }
    this.selectedMovie = null;
  }

  showSuccessMessage(listName) {
    // Create and show a toast notification
    const toastHtml = `
      <div class="toast align-items-center text-white bg-success border-0" role="alert" aria-live="assertive" aria-atomic="true">
        <div class="d-flex">
          <div class="toast-body">
            Successfully added "${this.selectedMovie.title}" to ${listName}!
          </div>
          <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
        </div>
      </div>
    `;

    this.showToast(toastHtml);
  }


  // Override rendering methods to show overlay
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

  // Clear search results
  clearResults() {
    this.hideResults();
    this.inputTarget.value = '';
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

  // Search for lists
  searchLists() {
    const keyword = this.inputTarget.value.trim();

    // Show loading state
    const loadingHtml = '<div class="text-center"><div class="spinner-border" role="status"><span class="visually-hidden">Loading...</span></div></div>';
    if (this.hasResultsContentTarget) {
      this.resultsContentTarget.innerHTML = loadingHtml;
    }
    this.resultsTarget.classList.remove('d-none');

    // Fetch lists from server
    fetch(`/lists/search?q=${encodeURIComponent(keyword)}`, {
      headers: {
        'Accept': 'application/json'
      }
    })
      .then(response => response.json())
      .then(data => {
        if (data.lists && data.lists.length > 0) {
          this.renderLists(data.lists);
        } else {
          this.showErrorMessage();
        }
      })
      .catch(error => {
        console.error('Error searching lists:', error);
        this.showErrorMessage();
      });
  }

  renderLists(lists) {
    const listData = { lists };
    const output = Mustache.render(this.listTemplate.innerHTML, listData);
    this.showResultsOverlay(output);
  }
}

// The search/render pipeline these two controllers share, defined once.
Object.assign(ListSearchController.prototype, TmdbSearchBehavior);

export default ListSearchController;
