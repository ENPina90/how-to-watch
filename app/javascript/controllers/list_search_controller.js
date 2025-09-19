import { Controller } from "@hotwired/stimulus";
import Mustache from "mustachejs";
import TmdbService from "services/tmdb_service";
import TmdbMapper from "services/tmdb_mapper";

export default class extends Controller {
  static targets = ["input", "results"];
  static values = {
    userLists: Array,
    apiKey: String
  };

  connect() {
    this.api = 'https://api.themoviedb.org/3/'
    this.apiKey = this.apiKeyValue || '7e1c210d0c877abff8a40398735ce605'
    this.tmdbService = new TmdbService(this.apiKey);
    this.movieTemplate = document.querySelector("#listSearchMovieTemplate");
    this.showTemplate = document.querySelector("#listSearchShowTemplate");
    this.selectedMovie = null;
  }

  // -----------------------------
  // SEARCH METHODS
  // -----------------------------

  tmdbSearch() {
    const keyword = this.inputTarget.value.trim();
    if (keyword.length < 2) {
      this.resultsTarget.innerHTML = '';
      return;
    }

    // Show loading state
    this.resultsTarget.innerHTML = '<div class="text-center"><div class="spinner-border" role="status"><span class="visually-hidden">Loading...</span></div></div>';

    const isImdbId = /^tt\d{4,}$/.test(keyword);

    this.tmdbService.fetchMovies(keyword, isImdbId)
      .then(data => {
        // Check if the API returned an error
        if (!data || data.status_code) {
          throw new Error(data.status_message || 'API request failed');
        }

        const movies = isImdbId ? data.movie_results : data.results;
        if (!movies || !Array.isArray(movies)) {
          this.resultsTarget.innerHTML = '<div class="alert alert-info">No results found.</div>';
          return;
        }

        const filteredMovies = movies.filter(movie => movie.vote_count >= 10 && movie.poster_path)
          .sort((a, b) => b.popularity - a.popularity)
          .slice(0, 10); // Limit to top 10 results

        if (filteredMovies.length === 0) {
          this.resultsTarget.innerHTML = '<div class="alert alert-info">No movies found matching your search.</div>';
          return;
        }

        const moviePromises = filteredMovies.map(movie =>
          this.tmdbService.fetchMovieDetails(movie.id)
            .then(details => TmdbMapper.mapMovieOrShowToTemplate(details))
            .catch(error => {
              console.error('Error fetching movie details:', error);
              return null;
            })
        );
        return Promise.all(moviePromises);
      })
      .then(moviesWithImdb => {
        if (!moviesWithImdb) return; // Handle case where we showed a message above

        const validMovies = moviesWithImdb.filter(movie => movie !== null);
        if (validMovies.length === 0) {
          this.resultsTarget.innerHTML = '<div class="alert alert-warning">Unable to load movie details.</div>';
          return;
        }

        this.renderMovies(validMovies);
      })
      .catch(error => {
        console.error('Error fetching movies:', error);
        this.resultsTarget.innerHTML = '<div class="alert alert-danger">Error searching for movies. Please try again.</div>';
      });
  }

  tmdbShow() {
    const keyword = this.inputTarget.value.trim();
    if (keyword.length < 2) {
      this.resultsTarget.innerHTML = '';
      return;
    }

    // Show loading state
    this.resultsTarget.innerHTML = '<div class="text-center"><div class="spinner-border" role="status"><span class="visually-hidden">Loading...</span></div></div>';

    const isImdbId = /^tt\d{4,}$/.test(keyword);

    this.tmdbService.fetchShows(keyword, isImdbId)
      .then(data => {
        // Check if the API returned an error
        if (!data || data.status_code) {
          throw new Error(data.status_message || 'API request failed');
        }

        const shows = isImdbId ? data.tv_results : data.results;
        if (!shows || !Array.isArray(shows)) {
          this.resultsTarget.innerHTML = '<div class="alert alert-info">No results found.</div>';
          return;
        }

        const filteredShows = shows.filter(show => show.vote_count >= 10 && show.poster_path)
          .sort((a, b) => b.popularity - a.popularity)
          .slice(0, 10); // Limit to top 10 results

        if (filteredShows.length === 0) {
          this.resultsTarget.innerHTML = '<div class="alert alert-info">No shows found matching your search.</div>';
          return;
        }

        const showPromises = filteredShows.map(show =>
          this.tmdbService.fetchShowDetails(show.id)
            .then(TmdbMapper.mapMovieOrShowToTemplate)
            .catch(error => {
              console.error('Error fetching show details:', error);
              return null;
            })
        );
        return Promise.all(showPromises);
      })
      .then(showsWithImdb => {
        if (!showsWithImdb) return; // Handle case where we showed a message above

        const validShows = showsWithImdb.filter(show => show !== null);
        if (validShows.length === 0) {
          this.resultsTarget.innerHTML = '<div class="alert alert-warning">Unable to load show details.</div>';
          return;
        }

        this.renderShows(validShows);
      })
      .catch(error => {
        console.error('Error fetching shows:', error);
        this.resultsTarget.innerHTML = '<div class="alert alert-danger">Error searching for shows. Please try again.</div>';
      });
  }

  // -----------------------------
  // RENDERING METHODS
  // -----------------------------

  renderMovies(movies) {
    const movieData = { movies };
    const output = Mustache.render(this.movieTemplate.innerHTML, movieData);
    this.resultsTarget.innerHTML = output;
  }

  renderShows(shows) {
    const showData = { movies: shows };
    const output = Mustache.render(this.showTemplate.innerHTML, showData);
    this.resultsTarget.innerHTML = output;
  }

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
    const modal = new bootstrap.Modal(document.getElementById('listSelectionModal'));
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
    if (!this.selectedMovie) return;

    const button = event.currentTarget;
    const listId = button.dataset.listId;
    const listName = button.dataset.listName;

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
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
      }
    })
    .then(response => {
      if (response.ok) {
        // Success - show confirmation and close modal
        this.showSuccessMessage(listName);
        this.closeModal();
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
    const modal = bootstrap.Modal.getInstance(document.getElementById('listSelectionModal'));
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

  showErrorMessage() {
    const toastHtml = `
      <div class="toast align-items-center text-white bg-danger border-0" role="alert" aria-live="assertive" aria-atomic="true">
        <div class="d-flex">
          <div class="toast-body">
            Failed to add "${this.selectedMovie.title}" to list. Please try again.
          </div>
          <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
        </div>
      </div>
    `;

    this.showToast(toastHtml);
  }

  showToast(toastHtml) {
    // Create toast container if it doesn't exist
    let toastContainer = document.querySelector('.toast-container');
    if (!toastContainer) {
      toastContainer = document.createElement('div');
      toastContainer.className = 'toast-container position-fixed bottom-0 end-0 p-3';
      document.body.appendChild(toastContainer);
    }

    // Add toast to container
    toastContainer.insertAdjacentHTML('beforeend', toastHtml);

    // Show the toast
    const toastElement = toastContainer.lastElementChild;
    const toast = new bootstrap.Toast(toastElement);
    toast.show();

    // Remove toast element after it's hidden
    toastElement.addEventListener('hidden.bs.toast', () => {
      toastElement.remove();
    });
  }

  // Clear search results
  clearResults() {
    this.resultsTarget.innerHTML = '';
    this.inputTarget.value = '';
  }
}
