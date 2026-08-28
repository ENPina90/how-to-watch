export default class TmdbMapper {
  // TMDB's own average, which is what the search already carries -- an IMDB rating would
  // cost an OMDB request per result. Null rather than a zero or 'N/A' when nothing has
  // been voted on, so a card can leave the line out instead of printing a placeholder.
  static rating(average, votes) {
    if (!average || votes === 0) return null;

    return Number(average).toFixed(1);
  }

  static mapMovieOrShowToTemplate(movieOrShow, entryId = null) {
    return {
      entryId: entryId,
      imdbID: movieOrShow.imdb_id,
      tmdbID: movieOrShow.id,
      Poster: movieOrShow.poster_path ? `https://image.tmdb.org/t/p/w500${movieOrShow.poster_path}` : 'N/A',
      Title: movieOrShow.title || movieOrShow.name,
      Year: movieOrShow.release_date ? movieOrShow.release_date.split('-')[0] : movieOrShow.first_air_date ? movieOrShow.first_air_date.split('-')[0] : 'N/A',
      Plot: movieOrShow.overview,
      Rating: TmdbMapper.rating(movieOrShow.vote_average, movieOrShow.vote_count),
      Genre: movieOrShow.genre_ids ? movieOrShow.genre_ids.join(', ') : 'N/A',
      Popularity: movieOrShow.popularity || 'N/A',
      totalSeasons: movieOrShow.number_of_seasons || 'N/A',
    };
  }

  static mapTmdbEpisodeToTemplate(episode, seriesImdbID, tmdbShowID) {
    return {
      Poster: episode.still_path ? `https://image.tmdb.org/t/p/w500${episode.still_path}` : 'N/A',
      Title: episode.name,
      Season: episode.season_number,
      Episode: episode.episode_number,
      Plot: episode.overview || null,
      Rating: TmdbMapper.rating(episode.vote_average, episode.vote_count),
      // Kept for ranking: two episodes at 8.4 are not equally well established.
      Votes: episode.vote_count || 0,
      imdbID: episode.imdb_id || seriesImdbID,
      seriesImdbID: seriesImdbID,
      tmdbID: tmdbShowID,
    };
  }
}
