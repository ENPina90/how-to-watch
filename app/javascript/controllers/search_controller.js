import { Controller } from "@hotwired/stimulus";
import Mustache from "mustachejs";

// Connects to data-controller="search"
export default class extends Controller {
  static targets = ["input", "results"];
  static values = { id: Number };

  connect() {
    this.api = "http://www.omdbapi.com/?";
    this.apiKey = "apikey=adf1f2d7";
    this.template = document.querySelector("#movieCardTemplate");
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
    const baseUrl = window.location.origin;
    const url = `${baseUrl}/lists/${this.idValue}?${this.params.toString()}`;
    fetch(url, { headers: { Accept: "text/plain" } })
      .then((response) => response.text())
      .then((data) => {
        this.resultsTarget.outerHTML = data;
      });
  }

  omdb() {
    let keyword = this.inputTarget.value;
    fetch(`${this.api}s=${keyword}&${this.apiKey}`)
      .then((response) => response.json())
      .then((data) => {
        const movieData = { movies: data.Search };
        const output = Mustache.render(this.template.innerHTML, movieData);
        this.resultsTarget.innerHTML = output;
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
