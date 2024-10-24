export default class TmdbService {
  constructor(apiKey) {
    this.api = "https://api.themoviedb.org/3/";
    this.apiKey = apiKey;
  }

  fetchMovies(keyword, isImdbId) {
    const url = isImdbId
      ? `${this.api}find/${keyword}?api_key=${this.apiKey}&external_source=imdb_id`
      : `${this.api}search/movie?api_key=${this.apiKey}&query=${keyword}`;
    return fetch(url).then(response => response.json());
  }

  fetchShows(keyword, isImdbId) {
    const url = isImdbId
      ? `${this.api}find/${keyword}?api_key=${this.apiKey}&external_source=imdb_id`
      : `${this.api}search/tv?api_key=${this.apiKey}&query=${keyword}`;
    return fetch(url).then(response => response.json());
  }

  fetchMovieDetails(tmdbId) {
    return fetch(`${this.api}movie/${tmdbId}?api_key=${this.apiKey}`).then(response => response.json());
  }

  fetchShowDetails(tmdbId) {
    // First, fetch external IDs to get the IMDb ID
    const externalIdsUrl = `${this.api}tv/${tmdbId}/external_ids?api_key=${this.apiKey}`;
    const showDetailsUrl = `${this.api}tv/${tmdbId}?api_key=${this.apiKey}`;

    return fetch(externalIdsUrl)
      .then(response => response.json())
      .then(externalIds => {
        if (externalIds.imdb_id) {
          // Now fetch the show details and attach the IMDb ID
          return fetch(showDetailsUrl)
            .then(response => response.json())
            .then(show => {
              show.imdb_id = externalIds.imdb_id;  // Attach IMDb ID to the show details
              console.log(show);
              return show;  // Return the full show details with IMDb ID
            });
        } else {
          console.log(`No IMDb ID found for TV show with TMDb ID: ${tmdbId}`);
          return null;
        }
      });
  }

  fetchEpisodes(tmdbId, season) {
    const url = `${this.api}tv/${tmdbId}/season/${season}?api_key=${this.apiKey}`;
    return fetch(url).then(response => response.json());
  }

  fetchEpisodeImdbId(tmdbId, season, episodeNumber) {
    const url = `${this.api}tv/${tmdbId}/season/${season}/episode/${episodeNumber}/external_ids?api_key=${this.apiKey}`;
    return fetch(url)
      .then(response => response.json())
      .then(externalIds => {
        return { imdb_id: externalIds.imdb_id };  // Return only IMDb ID
      });
  }
}
