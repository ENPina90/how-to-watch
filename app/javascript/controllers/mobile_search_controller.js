import { Controller } from "@hotwired/stimulus";
import Mustache from "mustachejs";
import * as bootstrap from "bootstrap";
import TmdbService from "services/tmdb_service";
import TmdbMapper from "services/tmdb_mapper";

export default class extends Controller {
  static targets = ["input", "results", "typeButtons", "resultsContent"];
  static values = {
    userLists: Array,
    apiKey: String
  };

  connect() {
    this.api = 'https://api.themoviedb.org/3/'
    this.apiKey = this.apiKeyValue || '7e1c210d0c877abff8a40398735ce605'
    this.tmdbService = new TmdbService(this.apiKey);
    this.movieTemplate = document.querySelector("#mobileSearchMovieTemplate");
    this.showTemplate = document.querySelector("#mobileSearchShowTemplate");
    this.currentSearchType = 'movie'; // Default to movie search

    console.log('Mobile search controller connected');
    console.log('Movie template found:', !!this.movieTemplate);
    console.log('Show template found:', !!this.showTemplate);
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

  showOverlay() {
    this.resultsTarget.classList.remove('d-none');
  }

  tmdbSearch() {
    const keyword = this.inputTarget.value.trim();

    // Show loading state
    const loadingHtml = '<div class="text-center"><div class="spinner-border" role="status"><span class="visually-hidden">Loading...</span></div></div>';
    if (this.hasResultsContentTarget) {
      this.resultsContentTarget.innerHTML = loadingHtml;
    } else {
      this.resultsTarget.innerHTML = loadingHtml;
    }
    this.resultsTarget.classList.remove('d-none');

    const isImdbId = /^tt\d{4,}$/.test(keyword);

    this.tmdbService.fetchMovies(keyword, isImdbId)
      .then(data => {
        // Check if the API returned an error
        if (!data || data.status_code) {
          throw new Error(data.status_message || 'API request failed');
        }

        const movies = isImdbId ? data.movie_results : data.results;
        if (!movies || !Array.isArray(movies)) {
          this.showErrorMessage();
          return;
        }

        const filteredMovies = movies.filter(movie => movie.vote_count >= 10 && movie.poster_path)
          .sort((a, b) => b.popularity - a.popularity)
          .slice(0, 10); // Limit to top 10 results

        if (filteredMovies.length === 0) {
          this.showErrorMessage();
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
          this.showErrorMessage();
          return;
        }

        this.renderMovies(validMovies);
      })
      .catch(error => {
        console.error('Error fetching movies:', error);
        this.showErrorMessage();
      });
  }

  tmdbShow() {
    const keyword = this.inputTarget.value.trim();

    // Show loading state
    const loadingHtml = '<div class="text-center"><div class="spinner-border" role="status"><span class="visually-hidden">Loading...</span></div></div>';
    if (this.hasResultsContentTarget) {
      this.resultsContentTarget.innerHTML = loadingHtml;
    } else {
      this.resultsTarget.innerHTML = loadingHtml;
    }
    this.resultsTarget.classList.remove('d-none');

    const isImdbId = /^tt\d{4,}$/.test(keyword);

    this.tmdbService.fetchShows(keyword, isImdbId)
      .then(data => {
        // Check if the API returned an error
        if (!data || data.status_code) {
          throw new Error(data.status_message || 'API request failed');
        }

        const shows = isImdbId ? data.tv_results : data.results;
        if (!shows || !Array.isArray(shows)) {
          this.showErrorMessage();
          return;
        }

        const filteredShows = shows.filter(show => show.vote_count >= 10 && show.poster_path)
          .sort((a, b) => b.popularity - a.popularity)
          .slice(0, 10); // Limit to top 10 results

        if (filteredShows.length === 0) {
          this.showErrorMessage();
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

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.hideResults();
    }
  }

  hideResults() {
    this.resultsTarget.classList.add('d-none');
    if (this.hasResultsContentTarget) {
      this.resultsContentTarget.innerHTML = '';
    } else {
      this.resultsTarget.innerHTML = '';
    }
  }

  // -----------------------------
  // ADD TO FAVORITES METHOD
  // -----------------------------

  addToFavorites(event) {
    event.preventDefault();
    const button = event.currentTarget;

    // Store the selected movie/show data
    const selectedItem = {
      imdbID: button.dataset.imdbId,
      tmdbID: button.dataset.tmdbId,
      title: button.dataset.title,
      poster: button.dataset.poster
    };

    console.log('Adding to favorites:', selectedItem);
    console.log('Button dataset:', button.dataset);

    // Show loading state
    const originalText = button.innerHTML;
    button.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Adding...';
    button.disabled = true;

    // Create form data
    const formData = new FormData();
    formData.append('imdb', selectedItem.imdbID);
    formData.append('tmdb', selectedItem.tmdbID);

    // Submit to the add_to_favorites endpoint
    fetch('/lists/add_to_favorites', {
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
        this.showSuccessMessage(selectedItem.title);
        // Reset button
        button.innerHTML = '<i class="fa-solid fa-check me-1"></i>Added!';
        button.classList.remove('btn-primary');
        button.classList.add('btn-success');
        button.disabled = true;
      } else {
        throw new Error(data.error || 'Failed to add to favorites');
      }
    })
    .catch(error => {
      console.error('Error adding to favorites:', error);
      this.showErrorMessage(selectedItem.title);
      // Reset button
      button.innerHTML = originalText;
      button.disabled = false;
    });
  }

  showSuccessMessage(title) {
    // Create and show a toast notification
    const toastHtml = `
      <div class="toast align-items-center text-white bg-success border-0" role="alert" aria-live="assertive" aria-atomic="true">
        <div class="d-flex">
          <div class="toast-body">
            Successfully added "${title}" to your favorites!
          </div>
          <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
        </div>
      </div>
    `;

    this.showToast(toastHtml);
  }

  showErrorMessage(title) {
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
