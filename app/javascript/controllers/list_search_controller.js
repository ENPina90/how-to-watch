import { Controller } from "@hotwired/stimulus";
import Mustache from "mustachejs";
import * as bootstrap from "bootstrap";
import TmdbService from "services/tmdb_service";
import TmdbMapper from "services/tmdb_mapper";

// What the /entries/new prompt has always capped a bulk add at.
const TOP_LIMIT = 20;
import { TmdbSearchBehavior } from "services/tmdb_search_behavior";

class ListSearchController extends Controller {
  static targets = ["input", "results", "typeButtons", "resultsContent"];
  static values = {
    userLists: Array,
    apiKey: String,
    // The channel being viewed, when the search happens on one. Blank everywhere else,
    // which reads as 0.
    currentListId: Number
  };

  connect() {
    this.api = 'https://api.themoviedb.org/3/'
    this.apiKey = this.apiKeyValue.length ? this.apiKeyValue : document.querySelector('meta[name="tmdb-key"]')?.content
    this.tmdbService = new TmdbService(this.apiKey);
    this.movieTemplate = document.querySelector("#listSearchMovieTemplate");
    this.showTemplate = document.querySelector("#listSearchShowTemplate");
    this.listTemplate = document.querySelector("#listSearchListTemplate");
    this.episodeTemplate = document.querySelector("#listSearchEpisodeTemplate");
    this.selectedMovie = null;
    this.currentSearchType = 'movie'; // Default to movie search

    // Listen for global modal open events
    this.boundHandleGlobalModal = this.handleGlobalModalOpen.bind(this);
    document.addEventListener('openListModal', this.boundHandleGlobalModal);

    // One reference for the controller's lifetime, so it can be both re-registered
    // harmlessly and actually removed again. Armed from here rather than from the first
    // render: dismissing the overlay should not depend on how it came to be open, and a
    // listener added inside a render is one more thing that can fail to be added.
    this.boundClickOutside = (event) => this.dismissOnOutsideClick(event);
    this.boundEscape = (event) => {
      if (event.key === "Escape") this.hideResults();
    };

    document.addEventListener('click', this.boundClickOutside);
    document.addEventListener('keydown', this.boundEscape);
  }

  disconnect() {
    // Clean up event listeners
    document.removeEventListener('openListModal', this.boundHandleGlobalModal);
    document.removeEventListener('click', this.boundClickOutside);
    document.removeEventListener('keydown', this.boundEscape);
  }

  // The overlay closes on a click outside it, whatever else has happened on the page since
  // it opened. Two things this guards against, both of which left it stuck open before:
  // a controller whose element has since been replaced -- its listener outlives it and
  // would hide an overlay that is no longer on the page -- and an exception on the way,
  // which would break every dismissal after the first rather than just one.
  dismissOnOutsideClick(event) {
    try {
      if (!document.contains(this.element)) return;
      if (this.element.contains(event.target)) return;

      this.hideResults();
    } catch (error) {
      console.error('Could not dismiss the search overlay:', error);
    }
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

  // The overlay belongs to the search box, not to the results: it opens when the box takes
  // focus, so the tabs that decide what is being searched are there to be chosen before a
  // character is typed.
  openOverlay() {
    if (this.inputTarget.value.trim().length < 2) return this.showPrompt();

    // A query with nothing behind it has not been run yet -- a page loaded with text
    // already in the box, or results explicitly cleared.
    if (!this.resultsBody().innerHTML.trim()) return this.performSearch();

    this.showOverlay();
    document.addEventListener('click', this.boundClickOutside);
  }

  showPrompt() {
    this.showResultsOverlay(
      '<div class="p-4 text-center text-muted">Type to search movies, series, anime or channels.</div>'
    );
  }

  // Universal search method that delegates based on current search type
  performSearch() {
    const keyword = this.inputTarget.value.trim();
    if (keyword.length < 2) {
      // Not hidden: the overlay was already open before this keystroke, and taking it away
      // on the first character -- then again on every deletion -- flickers the tabs in and
      // out from under the pointer.
      this.showPrompt();
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

  // Every + button in the results. What it adds is in its dataset; where it goes depends
  // on where the search was made from -- the channel you are looking at takes it outright,
  // and anywhere else has to be asked which channel.
  add(event) {
    event.preventDefault();
    const button = event.currentTarget;
    this.selectedMovie = this.itemFrom(button);

    if (this.currentListIdValue > 0) {
      this.addToCurrentList(button);
    } else {
      this.openPicker();
    }
  }

  itemFrom(button) {
    const data = button.dataset;

    return {
      imdbID: data.imdbId,
      tmdbID: data.tmdbId,
      title: data.title,
      poster: data.poster,
      // Only an episode or a season carries these.
      seriesImdbID: data.seriesImdbId,
      season: data.season,
      episode: data.episode,
      // 'entry' posts to the entries endpoint; 'season' imports a whole season.
      kind: data.kind || 'entry',
      type: data.type
    };
  }

  // On a channel page the overlay stays open and the button reports what happened, so a
  // run of additions is one search rather than one page load each.
  addToCurrentList(button) {
    const original = button.innerHTML;
    button.innerHTML = '<span class="spinner-border spinner-border-sm me-1"></span>Adding...';
    button.disabled = true;

    this.submit(this.currentListIdValue)
      .then(() => {
        // The channel holds something it did not a moment ago.
        this.index = null;

        button.innerHTML = '<i class="fas fa-check me-1"></i>Added';
        button.classList.replace('btn-primary', 'btn-success');
      })
      .catch(error => {
        console.error('Error adding to channel:', error);
        this.reportFailure(button, original);
      });
  }

  // On the button, never in the results: showErrorMessage replaces the overlay's contents
  // with "No results found", which is true of a search that found nothing and a lie about
  // an add that failed -- and it would throw away the results you were working through.
  reportFailure(button, original) {
    button.innerHTML = '<i class="fas fa-triangle-exclamation me-1"></i>Failed';
    button.disabled = false;

    setTimeout(() => { button.innerHTML = original; }, 3000);
  }

  // The other face of the + button: a result the channel already holds offers to take it
  // back out. Same endpoint the card's own delete button uses.
  remove(event) {
    event.preventDefault();
    const button = event.currentTarget;
    const original = button.innerHTML;

    button.innerHTML = '<span class="spinner-border spinner-border-sm me-1"></span>Removing...';
    button.disabled = true;

    fetch(`/entries/${button.dataset.entryId}`, {
      method: 'DELETE',
      headers: {
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content'),
        'Accept': 'text/vnd.turbo-stream.html'
      }
    })
      .then(response => {
        if (!response.ok) throw new Error('Failed to remove entry');

        return response.text();
      })
      .then(stream => {
        // The stream takes the card off the channel behind the overlay and corrects the
        // count, the same as deleting from the card itself.
        Turbo.renderStreamMessage(stream);
        this.index = null;

        button.innerHTML = '<i class="fas fa-check me-1"></i>Removed';
        button.classList.replace('btn-danger', 'btn-secondary');
      })
      .catch(error => {
        console.error('Error removing from channel:', error);
        this.reportFailure(button, original);
      });
  }

  openPicker() {
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

    modalTitle.textContent = `Add "${this.selectedMovie.title}" to a channel`;
    modalPoster.src = this.selectedMovie.poster;
    modalPoster.alt = this.selectedMovie.title;

    // Check if user has any lists
    if (this.userListsValue.length === 0) {
      listContainer.innerHTML = `
        <div class="text-center">
          <p class="text-muted mb-3">You don't have any channels yet!</p>
          <a href="/lists/new" class="btn btn-primary">Create Your First Channel</a>
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

    const chosen = this.pendingBatch
      ? this.addManyTo(listId, this.pendingBatch)
      : this.submit(listId);

    chosen
      .then(() => {
        // Picking a channel means going to it; adding to the one you are on does not.
        window.location.href = `/lists/${listId}?added=${this.selectedMovie.imdbID}`;
      })
      .catch(error => {
        console.error('Error adding to channel:', error);
        this.reportFailure(button, `<span>${listName}</span><small class="text-muted">${button.dataset.entriesCount || 0} entries</small>`);
      });
  }

  // One entry or a whole season, to whichever channel the caller settled on. Both are the
  // same endpoints the /entries/new page posts its forms to.
  submit(listId) {
    const item = this.selectedMovie;
    const season = item.kind === 'season';
    const body = new FormData();

    if (season) {
      body.append('tmdb', item.tmdbID);
      body.append('series_imdb', item.seriesImdbID || item.imdbID);
      body.append('series_name', item.title);
      body.append('season', item.season);
      body.append('media_type', item.type === 'anime' ? 'anime' : 'series');
    } else {
      body.append('imdb', item.seriesImdbID || item.imdbID);
      body.append('tmdb', item.tmdbID);
      // How the channel behind the overlay is grouped, so the card it streams back can be
      // put in the right section rather than only at the end of an ungrouped list.
      const criteria = document.querySelector('[data-channel-criteria]')?.dataset.channelCriteria;
      if (criteria) body.append('criteria', criteria);
      if (item.type) body.append('type', item.type);
      if (item.seriesImdbID) body.append('series_imdb', item.seriesImdbID);
      if (item.season) body.append('season', item.season);
      if (item.episode) body.append('episode', item.episode);
    }

    return fetch(`/lists/${listId}/${season ? 'add_season' : 'entries'}`, {
      method: 'POST',
      body: body,
      headers: {
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content'),
        // The entries endpoint answers with a turbo stream that carries the new card and
        // the updated count; a season import answers with json.
        'Accept': season ? 'application/json' : 'text/vnd.turbo-stream.html'
      }
    }).then(response => {
      if (!response.ok) throw new Error('Failed to add entry');
      if (season) return;

      // Applying it puts the entry in the channel behind the overlay -- at the end of the
      // list, where it was just given its position -- instead of waiting for a reload.
      return response.text().then(stream => Turbo.renderStreamMessage(stream));
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
    this.marked(movies).then(marked => {
      this.showResultsOverlay(
        Mustache.render(this.movieTemplate.innerHTML, { movies: marked, addLabel: this.addLabel() })
      );
    });
  }

  renderShows(shows) {
    this.marked(shows).then(marked => {
      this.showResultsOverlay(Mustache.render(this.showTemplate.innerHTML, {
        movies: marked,
        addLabel: this.addLabel(),
        // The one type the entries endpoint has to be told about: a show is its default.
        anime: this.currentSearchType === 'anime'
      }));
    });
  }

  // -----------------------------
  // WHAT THE CHANNEL ALREADY HOLDS
  // -----------------------------

  // Stamps each result with the id of the entry it already is on this channel, if any --
  // which is what turns its + button into a remove button.
  marked(results) {
    return this.entryIndex().then(entries => results.map(result => {
      const held = entries.find(entry => this.sameEntry(entry, result));

      return { ...result, entryId: held?.id };
    }));
  }

  // A movie or a series is its imdb id and nothing else; an episode is its series' id plus
  // its place in the run, since every episode of a show is filed under the same imdb id.
  sameEntry(entry, result) {
    if (result.Season) {
      return String(entry.season) === String(result.Season) &&
             String(entry.episode) === String(result.Episode) &&
             [entry.imdb, entry.series_imdb].includes(result.seriesImdbID);
    }

    return entry.imdb === result.imdbID && !entry.season;
  }

  // Fetched once per page rather than shipped with it, and dropped whenever this overlay
  // changes what the channel holds.
  entryIndex() {
    if (!(this.currentListIdValue > 0)) return Promise.resolve([]);

    this.index ||= fetch(`/lists/${this.currentListIdValue}/entry_index`, {
      headers: { 'Accept': 'application/json' }
    })
      .then(response => (response.ok ? response.json() : []))
      .catch(error => {
        console.error('Error loading channel contents:', error);
        return [];
      });

    return this.index;
  }

  // The + buttons name what they add rather than where it goes, the way the buttons on
  // the /entries/new page do: the search tab you are on is the media type.
  addLabel() {
    return { show: 'Series', anime: 'Anime' }[this.currentSearchType] || 'Movie';
  }

  // -----------------------------
  // EPISODE METHODS
  // -----------------------------

  // Steps the overlay from a show's result into its episodes, keeping the results behind
  // it so the button that goes back has something to go back to.
  seeEpisodes(event) {
    event.preventDefault();
    this.series = this.itemFrom(event.currentTarget);
    this.priorResults = this.resultsBody().innerHTML;

    // No round trip for the show: building this result already fetched its details, so
    // the card carries both the series' imdb id -- which is what an episode is filed
    // under -- and the season count. TMDB reports an unknown count as 'N/A'.
    this.series.seriesImdbID = this.series.imdbID;
    this.seasons = Number(event.currentTarget.dataset.seasons) || 1;

    this.showSeason(1);
  }

  changeSeason(event) {
    this.showSeason(Number(event.currentTarget.value));
  }

  showSeason(season) {
    if (!this.episodeTemplate) {
      return this.showEpisodeError(new Error('this page has no episode template'));
    }

    // One request per season: an episode is added under its series' imdb id, so there is
    // nothing to gain from fetching each episode's own.
    this.tmdbService.fetchEpisodes(this.series.tmdbID, season)
      .then(data => {
        // TMDB answers a bad id or key with a message rather than an error status, and
        // the season would otherwise render as simply empty.
        if (data.status_message) throw new Error(data.status_message);

        const episodes = (data.episodes || []).map(episode =>
          TmdbMapper.mapTmdbEpisodeToTemplate(episode, this.series.seriesImdbID, this.series.tmdbID)
        );

        return this.marked(episodes);
      })
      .then(episodes => {
        this.showResultsOverlay(Mustache.render(this.episodeTemplate.innerHTML, {
          series: this.series,
          season: season,
          seasonCount: this.seasons,
          seasons: Array.from({ length: this.seasons }, (_, i) => ({ number: i + 1 })),
          type: this.currentSearchType === 'anime' ? 'anime' : 'series',
          episodes: episodes
        }));

        // See the note on the picker in the template: the season it is showing is set
        // here rather than marked up as an attribute.
        const picker = this.resultsBody().querySelector('.season-picker');
        if (picker) picker.value = season;
      })
      .catch(error => this.showEpisodeError(error));
  }

  // Says what actually went wrong. showErrorMessage puts up "No results found", which is
  // true of a search that matched nothing and a lie about a request that failed -- it hid
  // the reason at exactly the moment there was one to report.
  showEpisodeError(error) {
    console.error('Error loading episodes:', error);

    this.resultsBody().innerHTML =
      `<div class="p-3 text-center text-muted">Could not load episodes: ${error.message}</div>`;
    this.resultsTarget.classList.remove('d-none');
  }

  // The show's best episodes, wherever they fall in the run. Every season is fetched --
  // there is no ranking endpoint -- and the ones with a rating are ordered by it, with the
  // vote count breaking ties so a single 10/10 vote cannot beat a well established 9.
  topEpisodes(event) {
    event.preventDefault();
    this.series = this.itemFrom(event.currentTarget);
    this.series.seriesImdbID = this.series.imdbID;
    this.seasons = Number(event.currentTarget.dataset.seasons) || 1;
    if (!this.priorResults) this.priorResults = this.resultsBody().innerHTML;

    this.resultsBody().innerHTML =
      '<div class="p-4 text-center"><div class="spinner-border" role="status"></div></div>';

    const seasons = Array.from({ length: this.seasons }, (_, i) => i + 1);

    Promise.all(seasons.map(season => this.tmdbService.fetchEpisodes(this.series.tmdbID, season)))
      .then(results => {
        const episodes = results.flatMap(data => (data.episodes || []).map(episode =>
          TmdbMapper.mapTmdbEpisodeToTemplate(episode, this.series.seriesImdbID, this.series.tmdbID)
        ));

        this.ranked = episodes
          .filter(episode => episode.Rating)
          .sort((a, b) => Number(b.Rating) - Number(a.Rating) || b.Votes - a.Votes)
          .slice(0, TOP_LIMIT);

        if (this.ranked.length === 0) throw new Error('none of these episodes are rated yet');

        return this.marked(this.ranked);
      })
      .then(episodes => {
        this.showResultsOverlay(Mustache.render(this.episodeTemplate.innerHTML, {
          series: this.series,
          top: true,
          type: this.currentSearchType === 'anime' ? 'anime' : 'series',
          episodes: episodes
        }));
      })
      .catch(error => this.showEpisodeError(error));
  }

  bySeason() {
    this.showSeason(1);
  }

  // How many, asked the way /entries/new asks it.
  openTopModal() {
    const modal = document.getElementById('topEpisodesModal');
    const slider = document.getElementById('topEpisodesSlider');
    const count = document.getElementById('topEpisodesCount');
    const confirm = document.getElementById('topEpisodesConfirm');
    if (!modal || !slider) return;

    slider.max = Math.min(this.ranked.length, TOP_LIMIT);
    slider.value = Math.min(Number(slider.value), Number(slider.max));
    count.textContent = slider.value;

    // Wired here rather than by data-action: this modal sits at the end of the body,
    // outside the element this controller is mounted on, where an action would not bind.
    slider.oninput = () => { count.textContent = slider.value; };
    confirm.onclick = () => {
      bootstrap.Modal.getInstance(modal)?.hide();
      this.addTopEpisodes(Number(slider.value));
    };

    new bootstrap.Modal(modal).show();
  }

  addTopEpisodes(count) {
    const episodes = this.ranked.slice(0, count);

    if (this.currentListIdValue > 0) return this.addManyTo(this.currentListIdValue, episodes);

    // Off a channel, the picker decides where they go -- one answer for the whole batch.
    this.pendingBatch = episodes;
    this.selectedMovie = { ...this.series, title: `${this.series.title} (${episodes.length} episodes)` };
    this.openPicker();
  }

  // One at a time: each post streams its own card back, and a channel is not a queue that
  // wants twenty simultaneous writes.
  addManyTo(listId, episodes) {
    const button = document.getElementById('topEpisodesConfirm');

    return episodes.reduce((chain, episode, i) => chain.then(() => {
      if (button) button.textContent = `Adding ${i + 1} of ${episodes.length}...`;
      this.selectedMovie = {
        imdbID: episode.seriesImdbID,
        seriesImdbID: episode.seriesImdbID,
        tmdbID: episode.tmdbID,
        title: episode.Title,
        season: episode.Season,
        episode: episode.Episode,
        kind: 'entry'
      };

      return this.submit(listId);
    }), Promise.resolve())
      .then(() => {
        this.index = null;
        this.pendingBatch = null;
        if (button) button.textContent = 'Add Episodes';
        this.topEpisodesAdded();
      })
      .catch(error => {
        console.error('Error adding top episodes:', error);
        if (button) button.textContent = 'Add Episodes';
        this.showEpisodeError(error);
      });
  }

  // Re-marks the view so what just landed on the channel shows as removable.
  topEpisodesAdded() {
    this.marked(this.ranked).then(episodes => {
      this.showResultsOverlay(Mustache.render(this.episodeTemplate.innerHTML, {
        series: this.series,
        top: true,
        type: this.currentSearchType === 'anime' ? 'anime' : 'series',
        episodes: episodes
      }));
    });
  }

  backToResults() {
    if (this.priorResults) this.showResultsOverlay(this.priorResults);
  }

  resultsBody() {
    return this.hasResultsContentTarget ? this.resultsContentTarget : this.resultsTarget;
  }

  showResultsOverlay(html) {
    this.resultsBody().innerHTML = html;
    this.resultsTarget.classList.remove('d-none');

    // Not `{ once: true }`: that fires on the first click *anywhere*, including one inside
    // the overlay, and is spent whether or not it closed anything. Clicking a result's
    // + button therefore disarmed the only thing listening, and the overlay could no
    // longer be dismissed. One bound reference registered repeatedly is a no-op after the
    // first, so this can be called on every render.
    document.addEventListener('click', this.boundClickOutside);
  }

  // Clear search results
  clearResults() {
    this.hideResults();
    this.resultsBody().innerHTML = '';
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
