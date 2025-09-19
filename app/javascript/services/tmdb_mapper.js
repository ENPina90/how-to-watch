export default class TmdbMapper {
  static mapMovieOrShowToTemplate(movieOrShow, entryId = null) {
    return {
      entryId: entryId,
      imdbID: movieOrShow.imdb_id,
      tmdbID: movieOrShow.id,
      Poster: movieOrShow.poster_path ? `https://image.tmdb.org/t/p/w500${movieOrShow.poster_path}` : 'N/A',
      Title: movieOrShow.title || movieOrShow.name,
      Year: movieOrShow.release_date ? movieOrShow.release_date.split('-')[0] : movieOrShow.first_air_date ? movieOrShow.first_air_date.split('-')[0] : 'N/A',
      Plot: movieOrShow.overview,
      Rating: movieOrShow.vote_average || 'N/A',
      Genre: movieOrShow.genre_ids ? movieOrShow.genre_ids.join(', ') : 'N/A',
      Popularity: movieOrShow.popularity || 'N/A',
      totalSeasons: movieOrShow.number_of_seasons || 'N/A',
    };
  }

  static mapTmdbEpisodeToTemplate(episode, imdbID) {
    return {
      Poster: episode.still_path ? `https://image.tmdb.org/t/p/w500${episode.still_path}` : 'N/A',
      Title: episode.name,
      Season: episode.season_number,
      Episode: episode.episode_number,
      imdbID: episode.imdb_id || imdbID,
      tmdbID: episode.id,
    };
  }
}
