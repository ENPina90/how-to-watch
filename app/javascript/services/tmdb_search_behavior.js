// Search behaviour shared by the navbar (list_search) and mobile search controllers.
// These six methods were byte-identical in both, so they are defined once here and mixed
// into each controller's prototype. They still run as controller methods: `this` is the
// controller, so targets like `inputTarget` and collaborators like `tmdbService` resolve
// exactly as before.
//
// This lives under services/ rather than controllers/ deliberately — Stimulus eager-loads
// everything under controllers/ and would try to register a mixin as a controller.
import TmdbMapper from "services/tmdb_mapper";

export const TmdbSearchBehavior = {
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
  },

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
          this.resultsTarget.innerHTML = '<div class="alert alert-warning">Unable to load series details.</div>';
          return;
        }

        this.renderShows(validShows);
      })
      .catch(error => {
        console.error('Error fetching shows:', error);
        this.resultsTarget.innerHTML = '<div class="alert alert-danger">Error searching for series. Please try again.</div>';
      });
  },

  showOverlay() {
    this.resultsTarget.classList.remove('d-none');
  },

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.hideResults();
    }
  },

  // Hides, and only hides. Emptying the overlay here meant that clicking away threw the
  // results out from under a query still sitting in the box, so coming back to it -- which
  // is now as easy as focusing the box -- showed nothing. What is on screen when it closes
  // is what is there when it opens again; the search itself clears them when the query
  // changes, and clearResults() empties them when that is what is actually meant.
  hideResults() {
    this.resultsTarget.classList.add('d-none');
  },

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
};
