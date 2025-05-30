# Pin npm packages by running ./bin/importmap

pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"
pin "bootstrap", to: "https://ga.jspm.io/npm:bootstrap@5.2.3/dist/js/bootstrap.esm.js"
pin "@popperjs/core", to: "https://unpkg.com/@popperjs/core@2.11.2/dist/esm/index.js"
pin "mustachejs", to: "https://cdnjs.cloudflare.com/ajax/libs/mustache.js/4.2.0/mustache.min.js"
pin "sortablejs", to: "https://ga.jspm.io/npm:sortablejs@1.15.3/modular/sortable.esm.js"
