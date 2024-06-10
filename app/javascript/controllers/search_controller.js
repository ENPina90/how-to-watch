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
    let keyword = this.inputTarget.value;
    fetch(`${this.api}s=${keyword}&apikey=${this.apiKeys[this.randomNumber(2)]}`)
      .then((response) => response.json())
      .then((data) => {
        if (!data.Error) {
          // console.log(data.Search[0]);
          const movieData = { movies: data.Search };
          const output = Mustache.render(
            this.movieTemplate.innerHTML,
            movieData
          );
          this.resultsTarget.innerHTML = output;
          let countElement = `<div>
              <h3 class="align-self-start">Results <small data-search-target="count">${data.Search.length}</small></h3>
            </div>`;
          this.resultsTarget.insertAdjacentHTML("afterbegin", countElement);
        }
      });
  }

  omdbShow() {
    let keyword = this.inputTarget.value;
    // console.log(`${this.api}t=${keyword}&${this.apiKey}&type=series`);
    fetch(`${this.api}t=${keyword}&apikey=${this.apiKeys[this.randomNumber(2)]}&type=series`)
      .then((response) => response.json())
      .then((data) => {
        if (!data.Error) {
          console.log(data);
          const movieData = { movies: data };
          const output = Mustache.render(
            this.showTemplate.innerHTML,
            movieData
          );
          this.resultsTarget.innerHTML = output;
        }
      });
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
    let keyword = this.inputTarget.value;
    let season = this.seasonTarget.value;
    season = `&season=${season ? season : 1}`;
    let episode = this.episodeTarget.value;
    episode = `${episode ? "&episode=" + episode : ""}`;
    let url = `${this.api}t=${keyword}${season}${episode}&apikey=${this.apiKeys[this.randomNumber(2)]}&type=series`;

    fetch(url)
      .then((response) => response.json())
      .then((data) => {
        if (!data.Error) {
          if (data.Episodes && data.Episodes.length > 0) {
            const firstEpisode = data.Episodes[0];
            if (JSON.stringify(firstEpisode) === JSON.stringify(this.previousFirstEpisode)) {
              console.log("First episode data has not changed");
              return;
            }
            this.previousFirstEpisode = firstEpisode;
          }
          this.resultsTarget.innerHTML = "";
          if (data.Episodes) {
            // Create an array of promises for fetching each episode
            const episodePromises = data.Episodes.map((episode) => {
              const episodeUrl = `${this.api}i=${episode.imdbID}&apikey=${this.apiKeys[this.randomNumber(2)]}`;
              console.log(episodeUrl);
              return fetch(episodeUrl).then((response) => response.json());
            });

            // Wait for all fetch requests to complete
            Promise.all(episodePromises).then((episodes) => {
              episodes.forEach((episodeData) => {
                const movieData = { movies: episodeData };
                const output = Mustache.render(this.episodeTemplate.innerHTML, movieData);
                this.resultsTarget.insertAdjacentHTML("beforeend", output);
              });
            });
          } else {
            this.episodeInsert(`${this.api}i=${data.imdbID}&${this.apiKeys[this.randomNumber(2)]}`);
          }
        }
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
    fetch(`${this.api}i=${imdbID}&apikey=${this.apiKeys[this.randomNumber(3)]}`)
      .then((response) => response.json())
      .then((data) => {
        this.createEntry(data);
      });
  }

  randomNumber(x) {
    return Math.floor(Math.random() * x);
  }
}
