import { Controller } from "@hotwired/stimulus";
import Mustache from "mustachejs";

// Connects to data-controller="search"
export default class extends Controller {
  static targets = ["input", "season", "episode", "results"];
  static values = { id: Number };

  connect() {
    this.api = "http://www.omdbapi.com/?";
    this.apiKey = "apikey=eb34d99";
    this.movieTemplate = document.querySelector("#movieCardTemplate");
    this.showTemplate = document.querySelector("#showCardTemplate");
    this.episodeTemplate = document.querySelector("#episodeCardTemplate");
    // URLSearchParams creates an object from the query string in the URL
    this.params = new URLSearchParams(window.location.search);
  }

  entries(event) {
    event.preventDefault();
    // creates or updates the query string
    if (event.type == "click") {
      this.params.set("criteria", event.currentTarget.text);
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
    fetch(`${this.api}s=${keyword}&${this.apiKey}`)
      .then((response) => response.json())
      .then((data) => {
        if (!data.Error) {
          const movieData = { movies: data.Search };
          const output = Mustache.render(
            this.movieTemplate.innerHTML,
            movieData
          );
          this.resultsTarget.innerHTML = output;
        }
      });
  }

  omdbShow() {
    let keyword = this.inputTarget.value;
    console.log(`${this.api}t=${keyword}&${this.apiKey}&type=series`);
    fetch(`${this.api}t=${keyword}&${this.apiKey}&type=series`)
      .then((response) => response.json())
      .then((data) => {
        if (!data.Error) {
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
    let url = `${this.api}t=${keyword}${season}${episode}&${this.apiKey}&type=series`;
    console.log(url);
    fetch(url)
      .then((response) => response.json())
      .then((data) => {
        if (!data.Error) {
          this.resultsTarget.innerHTML = "";
          console.log(data);
          if (data.Episodes) {
            data.Episodes.forEach((episode) => {
              console.log(episode);
              this.episodeInsert(
                `${this.api}i=${episode.imdbID}&${this.apiKey}`
              );
            });
          } else {
            this.episodeInsert(`${this.api}i=${data.imdbID}&${this.apiKey}`);
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
    fetch(`${this.api}i=${imdbID}&${this.apiKey}`)
      .then((response) => response.json())
      .then((data) => {
        this.createEntry(data);
      });
  }
}
