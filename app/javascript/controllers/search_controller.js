import { Controller } from "@hotwired/stimulus";
import Mustache from "mustachejs";
import TmdbService from "services/tmdb_service";
import TmdbMapper from "services/tmdb_mapper";

export default class extends Controller {
  static targets = ["input", "season", "episode", "results", "count"];
  static values = { id: Number };

  connect() {
    this.api = 'https://api.themoviedb.org/3/'
    this.apiKey = '7e1c210d0c877abff8a40398735ce605'
    this.tmdbService = new TmdbService(this.apiKey);
    this.movieTemplate = document.querySelector("#movieCardTemplate");
    this.showTemplate = document.querySelector("#showCardTemplate");
    this.episodeTemplate = document.querySelector("#episodeCardTemplate");

    this.entriesInList = (this.element.dataset.searchEntries || "").split('/').map(entry => {
      const [id, imdb] = entry.split('-');
      return { id, imdb };
    });
  }

  // -----------------------------
  // SEARCH METHODS
  // -----------------------------

  tmdbSearch() {
    const keyword = this.inputTarget.value.trim();
    const isImdbId = /^tt\d{4,}$/.test(keyword);

    this.tmdbService.fetchMovies(keyword, isImdbId)
      .then(data => {
        const movies = isImdbId ? data.movie_results : data.results;
        const filteredMovies = movies.filter(movie => movie.vote_count >= 10 && movie.poster_path)
          .sort((a, b) => b.popularity - a.popularity);

        const moviePromises = filteredMovies.map(movie =>
          this.tmdbService.fetchMovieDetails(movie.id)
            .then(details => TmdbMapper.mapMovieOrShowToTemplate(details))
        );
        return Promise.all(moviePromises);
      })
      .then(moviesWithImdb => {
        const validMovies = moviesWithImdb.filter(movie => movie !== null);

        // Add 'isInList' flag to each movie

        const moviesWithInListFlag = validMovies.map(movie => {
          const entry = this.entriesInList.find(entry => entry.imdb === movie.imdbID);
          movie.isInList = !!entry;
          movie.entryId = entry ? entry.id : null;
          return movie;
        });

        this.renderMovies(moviesWithInListFlag);
      })
      .catch(error => console.error('Error fetching movies:', error));
  }

  tmdbShow() {
    const keyword = this.inputTarget.value.trim();
    const isImdbId = /^tt\d{4,}$/.test(keyword);

    this.tmdbService.fetchShows(keyword, isImdbId)
      .then(data => {
        const shows = isImdbId ? data.tv_results : data.results;
        const filteredShows = shows.filter(show => show.vote_count >= 10 && show.poster_path)
          .sort((a, b) => b.popularity - a.popularity);

        const showPromises = filteredShows.map(show => this.tmdbService.fetchShowDetails(show.id).then(TmdbMapper.mapMovieOrShowToTemplate));
        return Promise.all(showPromises);
      })
      .then(showsWithImdb => {
        const validShows = showsWithImdb.filter(show => show !== null);
        this.renderShows(validShows);
      })
      .catch(error => console.error('Error fetching shows:', error));
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

  renderEpisodesForSeason(tmdbId, imdbId, season, dropdownHtml = '') {
    this.tmdbService.fetchEpisodes(tmdbId, season)
      .then(data => {
        console.log(data.episodes);
        console.log(imdbId);

        // Fetch IMDb ID for each episode
        const episodePromises = data.episodes.map(episode => {
          return this.tmdbService.fetchEpisodeImdbId(tmdbId, season, episode.episode_number)
            .then(imdbData => {
              episode.imdb_id = imdbData.imdb_id;  // Attach the IMDb ID to the episode
              return episode;
            });
        });

        // Once all episodes have their IMDb ID, map them to the template
        Promise.all(episodePromises).then(episodesWithImdb => {
          const episodeData = {
            movies: episodesWithImdb.map(episode => TmdbMapper.mapTmdbEpisodeToTemplate(episode, imdbId))
          };
          console.log(episodeData);
          const episodesHtml = Mustache.render(this.episodeTemplate.innerHTML, episodeData);
          this.resultsTarget.innerHTML = dropdownHtml + episodesHtml;
        });
      })
      .catch(error => console.error('Error fetching episodes:', error));
  }


  // -----------------------------
  // SEASON DROPDOWN METHODS
  // -----------------------------

  seeEpisodes(event) {
    const tmdbId = event.currentTarget.dataset.tmdbId;
    const season = 1;

    this.tmdbService.fetchShowDetails(tmdbId)
      .then(showData => {
        const numberOfSeasons = showData.number_of_seasons;
        const seriesName = showData.name;
        const dropdownHtml = this.renderSeasonDropdown(seriesName, numberOfSeasons, tmdbId, season);
        this.renderEpisodesForSeason(tmdbId, showData.imdb_id, season, dropdownHtml);
      })
      .catch(error => console.error('Error fetching show details:', error));
  }

  changeSeason(event) {
    const tmdbId = event.target.dataset.tmdbId;
    const selectedSeason = event.target.value;

    // Log the tmdbId and season to ensure they are correct
    console.log('Selected TMDb ID:', tmdbId);
    console.log('Selected Season:', selectedSeason);

    const fetchUrl = `${this.api}tv/${tmdbId}?api_key=${this.apiKey}`;

    console.log('Fetching show details from:', fetchUrl);

    fetch(fetchUrl)
      .then(response => response.json())
      .then(showData => {
        if (!showData.errors) {
          const numberOfSeasons = showData.number_of_seasons;
          const seriesName = showData.name;

          // Inject the season dropdown with the selected season
          const dropdownHtml = this.renderSeasonDropdown(seriesName, numberOfSeasons, tmdbId, selectedSeason);

          // Fetch the episodes for the selected season
          this.renderEpisodesForSeason(tmdbId, showData.imdb_id, selectedSeason, dropdownHtml);
        } else {
          console.error('Error fetching show details:', showData.errors);
        }
      })
      .catch(error => console.error('Error fetching show details:', error));
  }


  renderSeasonDropdown(seriesName, numberOfSeasons, tmdbId, selectedSeason = 1) {
    let dropdownHtml = `
      <div class="d-flex align-items-center mb-3">
        <h4 class="mr-3">${seriesName}</h4>
        <div class="form-group">
          <label for="seasonSelect" class="mr-2">Select Season:</label>
          <select id="seasonSelect" class="form-control" data-tmdb-id="${tmdbId}" data-action="change->search#changeSeason">
    `;

    for (let i = 1; i <= numberOfSeasons; i++) {
      const selected = i == selectedSeason ? 'selected' : '';
      dropdownHtml += `<option value="${i}" ${selected}>Season ${i}</option>`;
    }

    dropdownHtml += `
          </select>
        </div>
      </div>
    `;

    return dropdownHtml;
  }
}
