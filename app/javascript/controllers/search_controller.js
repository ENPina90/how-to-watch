import { Controller } from "@hotwired/stimulus"
import Mustache from "mustachejs";


// Connects to data-controller="search"
export default class extends Controller {
  static targets = [ "input", "results"]
  static values = { id: Number }

  connect() {
    this.api = 'http://www.omdbapi.com/?'
    this.apiKey = 'apikey=adf1f2d7'
    console.log('howdy from stimulus');
    console.log(this.resultsTarget);
    this.template = document.querySelector("#movieCardTemplate").innerHTML
    console.log(this.idValue);
  }

  omdb() {
    let keyword = this.inputTarget.value
    console.log(keyword);
    console.log('$this is making an api call...');
    fetch(`${this.api}s=${keyword}&${this.apiKey}`)
      .then(response => response.json())
      .then((data) => {
        // data.Search.forEach((movie) => {
          // movie.url = `${window.location.origin}/lists/${this.idValue}/entries/imdb=${movie.imdbID}`
        //   movie.url = `/entries`
        //   console.log(movie);
        // })
        // console.log(data);
        const movieData = { "movies": data.Search }
        const output = Mustache.render(this.template, movieData);
        // console.log(output);
        this.resultsTarget.innerHTML = output;
    })
  }

  createEntry(jsonMovie) {
    const url = `${window.location.origin}/lists/${this.idValue}/entries`
    fetch(url, {
      method: 'POST',
      body: JSON.stringify(jsonMovie)
    })
      .then(response => {
        window.location.href = response.url

      })
      //   response.text())
      // .then((data) => {
      //   console.log(data);
        // Replace entire document with response
        // document.innerHTML = data
      // })
  }

  add(event) {
    const imdbID = event.currentTarget.dataset.imdb
    // console.log(imdbID);
    fetch(`${this.api}i=${imdbID}&${this.apiKey}`)
      .then(response => response.json())
      .then((data) => {
        this.createEntry(data)
      })
  }
}
