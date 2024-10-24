import { Controller } from "@hotwired/stimulus";
import Mustache from "mustachejs";

// Connects to data-controller="search"
export default class extends Controller {
  static targets = ["input", "season", "episode", "results", "count"];
  static values = { id: Number };

  connect() {
    this.api = "http://www.omdbapi.com/?";
    this.apiKeys = this.data.get("key").split('-');
    this.movieTemplate = document.querySelector("#movieCardTemplate");
    this.showTemplate = document.querySelector("#showCardTemplate");
    this.episodeTemplate = document.querySelector("#episodeCardTemplate");
    // URLSearchParams creates an object from the query string in the URL
    this.params = new URLSearchParams(window.location.search);
    this.imdbID = ''
    this.previousCount = 0
    this.previousEpisodes = [];
  }

  entries(event) {
    event.preventDefault();
    // creates or updates the query string
    if (event.type == "click") {
      document.querySelectorAll("a").forEach((link) => {
        link.style.color = "black";
      });
      // checks if first or second click
      if (
        this.params.get("criteria") == event.currentTarget.text &&
        !this.params.get("sort")
      ) {
        this.params.set("sort", "reverse");
      } else {
        this.params.delete("sort");
      }
      this.params.set("criteria", event.currentTarget.text);
      event.currentTarget.style.color = "#1A936F";
    }
    if (this.inputTarget.value) {
      this.params.set("query", this.inputTarget.value);
    }
    if (this.inputTarget.value.length === 0) {
      this.params.delete("query");
    }
    const baseUrl = window.location.origin;
    const url = `${baseUrl}/lists/${this.idValue}?${this.params.toString()}`;
    fetch(url, { headers: { Accept: "text/plain" } })
      .then((response) => response.text())
      .then((data) => {
        this.resultsTarget.outerHTML = data;
      });
    // updates the url bar in real time and adds to history, to maintain search through page load
    window.history.replaceState(
      { additionalInformation: "updated with Stimulus" },
      "new page",
      url
    );
  }

  omdb() {
    const apiKey = this.randomAPIKey();
    const keyword = this.inputTarget.value;
    const pattern = /^tt\d{4,}$/;
    const isId = pattern.test(keyword);
    const fetchUrl = isId
      ? `http://www.omdbapi.com/?i=${keyword}&apikey=${apiKey}`
      : `${this.api}s=${keyword}&apikey=${apiKey}`;
    console.log(fetchUrl);
    fetch(fetchUrl)
      .then((response) => response.json())
      .then((data) => {
        if (!data.Error) {
          let movieData;
          if (isId) {
            movieData = { movies: [data] }; // Wrap in an array to maintain consistency
          } else {
            // Filter out movies with no poster
            const moviesWithPoster = data.Search.filter(movie => movie.Poster !== 'N/A');
            movieData = { movies: moviesWithPoster };
          }


          const output = Mustache.render(this.movieTemplate.innerHTML, movieData);
          this.resultsTarget.innerHTML = output;

          const countElement = `
          <div>
            <h3 class="align-self-start">Results <small data-search-target="count">${movieData.movies.length}</small></h3>
          </div>`;
          this.resultsTarget.insertAdjacentHTML("afterbegin", countElement);
        }
      })
      .catch((error) => console.error('Error fetching data:', error));
  }

  omdbShow() {
    const apiKey = this.randomAPIKey();
    const keyword = this.inputTarget.value;
    const pattern = /^tt\d{4,}$/;
    const isId = pattern.test(keyword);
    const fetchUrl = isId
      ? `http://www.omdbapi.com/?i=${keyword}&apikey=${apiKey}`
      : `${this.api}t=${keyword}&apikey=${apiKey}`;
    console.log(fetchUrl);
    fetch(fetchUrl)
      .then((response) => response.json())
      .then((data) => {
        if (!data.Error) {
          console.log(data);

          // Filter out movies and only render if it's a series
          if (data.Type !== 'movie') {
            this.imdbID = data['imdbID'];
            const movieData = { movies: data };
            const output = Mustache.render(
              this.showTemplate.innerHTML,
              movieData
            );
            this.resultsTarget.innerHTML = output;
          } else {
            console.log("Filtered out result because it's a movie.");
          }
        }
      });
    console.log("episode:", this.episodeTarget.value, " season:", this.seasonTarget.value);
    if (this.episodeTarget.value !== "" || this.seasonTarget.value !== "") {
      console.log('not empty');
      this.omdbEpisode()
    }
  }

  episodeInsert(url) {
    fetch(url)
      .then((response) => response.json())
      .then((data) => {
        const movieData = { movies: data };
        const output = Mustache.render(
          this.episodeTemplate.innerHTML,
          movieData
        );
        this.resultsTarget.insertAdjacentHTML("beforeend", output);
      });
  }

  omdbEpisode() {
    let season = this.seasonTarget.value;
    season = `&season=${season ? season : 1}`;
    let episode = this.episodeTarget.value;
    episode = `${episode ? "&episode=" + episode : ""}`;
    let url = `${this.api}i=${this.imdbID}${season}${episode}&apikey=${this.randomAPIKey()}&type=series`;
    console.log(url);
    fetch(url)
      .then((response) => response.json())
      .then((data) => {
        if (!data.Error) {
          console.log(this.previousCount);
          if (data.Episodes) {
            console.log(data.Episodes.length);
            const firstEpisode = data.Episodes[0];
            if (JSON.stringify(firstEpisode) === JSON.stringify(this.previousFirstEpisode)) {
              console.log("First episode data has not changed");
              return;
            }
            this.previousFirstEpisode = firstEpisode;
          }
          this.resultsTarget.innerHTML = "";
          if (data.Episodes) {
            this.previousCount = data.Episodes.length
            // Create an array of promises for fetching each episode
            const episodePromises = data.Episodes.map((episode) => {
              const episodeUrl = `${this.api}i=${episode.imdbID}&apikey=${this.randomAPIKey()}`;
              return fetch(episodeUrl).then((response) => response.json());
            });

            // Wait for all fetch requests to complete
            Promise.all(episodePromises).then((episodes) => {
              episodes.forEach((episodeData) => {
                if (episodeData.Type !== 'movie') {
                  const movieData = { movies: episodeData };
                  const output = Mustache.render(this.episodeTemplate.innerHTML, movieData);
                  this.resultsTarget.insertAdjacentHTML("beforeend", output);
                }
              });
            });
          } else {
            this.episodeInsert(`${this.api}i=${data.imdbID}&apikey=${this.randomAPIKey()}`);
          }
        }
        this.previousCount = JSON.stringify(data).length
      });
  }

  createEntry(jsonMovie) {
    const url = `${window.location.origin}/lists/${this.idValue}/entries`;
    fetch(url, {
      method: "POST",
      body: JSON.stringify(jsonMovie),
    }).then((response) => {
      window.location.href = response.url;
    });
  }

  add(event) {
    const imdbID = event.currentTarget.dataset.imdb;
    // console.log(imdbID);
    fetch(`${this.api}i=${imdbID}&apikey=${this.randomAPIKey()}`)
      .then((response) => response.json())
      .then((data) => {
        this.createEntry(data);
      });
  }

  randomAPIKey() {
    let randomNum = Math.floor(Math.random() * 3);
    return this.apiKeys[randomNum]
    // return this.apiKeys[2]
  }
}
