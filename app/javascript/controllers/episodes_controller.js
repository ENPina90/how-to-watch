import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["seasonSelector", "episodesList", "currentEpisodeInfo"];
  static values = {
    tmdbId: String,
    seriesImdb: String,
    currentSeason: Number,
    currentEpisode: Number
  };

  connect() {
    console.log('Episodes controller connected');
    console.log('TMDB ID:', this.tmdbIdValue);
    console.log('Current Season:', this.currentSeasonValue);
    console.log('Current Episode:', this.currentEpisodeValue);

    this.apiKey = '7e1c210d0c877abff8a40398735ce605';
    this.api = 'https://api.themoviedb.org/3/';

    // Load episodes for current season
    if (this.hasTmdbIdValue && this.tmdbIdValue) {
      this.loadEpisodesForSeason(this.currentSeasonValue || 1);
    } else {
      console.error('No TMDB ID provided to episodes controller');
      if (this.hasEpisodesListTarget) {
        this.episodesListTarget.innerHTML = `
          <div class="text-center text-danger">
            <i class="fa-solid fa-exclamation-triangle mb-2"></i>
            <p style="font-size: 0.85rem;">TMDB ID required</p>
          </div>
        `;
      }
    }
  }

  changeSeason(event) {
    const selectedSeason = parseInt(event.target.value);
    this.loadEpisodesForSeason(selectedSeason);
  }

  loadEpisodesForSeason(season) {
    const url = `${this.api}tv/${this.tmdbIdValue}/season/${season}?api_key=${this.apiKey}`;

    // Show loading state
    this.episodesListTarget.innerHTML = `
      <div class="text-center text-muted">
        <div class="spinner-border spinner-border-sm" role="status">
          <span class="visually-hidden">Loading...</span>
        </div>
        <p class="mt-2" style="font-size: 0.85rem;">Loading episodes...</p>
      </div>
    `;

    fetch(url)
      .then(response => response.json())
      .then(data => {
        this.renderEpisodes(data.episodes, season);
      })
      .catch(error => {
        console.error('Error fetching episodes:', error);
        this.episodesListTarget.innerHTML = `
          <div class="text-center text-danger">
            <i class="fa-solid fa-exclamation-triangle mb-2"></i>
            <p style="font-size: 0.85rem;">Error loading episodes</p>
          </div>
        `;
      });
  }

  renderEpisodes(episodes, season) {
    if (!episodes || episodes.length === 0) {
      this.episodesListTarget.innerHTML = `
        <div class="text-center text-muted">
          <p style="font-size: 0.85rem;">No episodes found</p>
        </div>
      `;
      return;
    }

    const episodesHTML = episodes.map(episode => {
      // Convert to numbers for proper comparison
      const currentSeason = parseInt(this.currentSeasonValue);
      const currentEpisode = parseInt(this.currentEpisodeValue);
      const isCurrent = (parseInt(season) === currentSeason && episode.episode_number === currentEpisode);

      const activeStyles = isCurrent
        ? 'background-color: rgba(255, 255, 255, 0.15) !important; font-weight: 600 !important;'
        : '';
      const episodeNumberColor = 'rgba(255, 255, 255, 0.6)';

      return `
        <a href="/watch_now?imdb=${this.seriesImdbValue}&title=${encodeURIComponent(episode.name)}&type=tv&tmdb=${this.tmdbIdValue}&season=${season}&episode=${episode.episode_number}"
           class="episode-item ${isCurrent ? 'active' : ''}"
           style="color: #ffffff !important; text-decoration: none !important; ${activeStyles}"
           data-action="click->episodes#selectEpisode"
           data-season="${season}"
           data-episode="${episode.episode_number}"
           data-episode-name="${this.escapeHtml(episode.name)}"
           data-episode-overview="${this.escapeHtml(episode.overview || '')}">
          <div class="d-flex align-items-center">
            <div class="episode-number" style="color: ${episodeNumberColor} !important;">
              ${episode.episode_number}.&nbsp;
            </div>
            <div class="episode-title-container flex-grow-1">
              <span class="episode-title" style="color: #ffffff !important;">${this.escapeHtml(episode.name)}</span>
            </div>
          </div>
        </a>
      `;
    }).join('');

    this.episodesListTarget.innerHTML = episodesHTML;
  }

  selectEpisode(event) {
    const season = event.currentTarget.dataset.season;
    const episode = event.currentTarget.dataset.episode;
    const episodeName = event.currentTarget.dataset.episodeName;
    const episodeOverview = event.currentTarget.dataset.episodeOverview;

    // Update current episode info
    this.updateCurrentEpisodeInfo(season, episode, episodeName, episodeOverview);
  }

  updateCurrentEpisodeInfo(season, episode, name, overview) {
    const html = `
      <div>
        <p class="text-muted mb-2" style="font-size: 0.8rem;">
          Season ${season}, Episode ${episode}
        </p>
        <h6 class="text-white mb-3" style="font-size: 0.95rem; font-weight: 600; line-height: 1.3;">
          ${name}
        </h6>
        ${overview ? `
          <p class="text-white-50 mb-0" style="font-size: 0.8rem; line-height: 1.4;">
            ${overview}
          </p>
        ` : `
          <p class="text-white-50 mb-0 fst-italic" style="font-size: 0.8rem;">
            No synopsis available
          </p>
        `}
      </div>
    `;

    this.currentEpisodeInfoTarget.innerHTML = html;
  }

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  truncateText(text, maxLength) {
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength) + '...';
  }
}
