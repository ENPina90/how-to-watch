import { Controller } from "@hotwired/stimulus";
import { driver } from "driver.js";

// The guided tour. Four pages -- home, a channel, a search inside it, and /cable -- each a
// handful of stops that point at something real on the page and, here and there, work it
// for the viewer: typing a search, picking a filter, flipping a channel.
//
// The server draws this controller only while a tour is running (see TourHelper), and says
// which pages this visitor may reach; a page they would be bounced from is not in the list.
// Where the tour has got to is the `tour` session cookie, written before every move between
// pages and deleted when the tour ends, however it ends. If the page under the controller
// is not the one the cookie names, the viewer has gone somewhere else on their own and the
// tour quietly stops.
//
// A stop whose element is missing -- the sidebar a guest does not have, a channel with no
// filters, a search that found nothing -- is left out rather than shown pointing at
// nothing. Each stop's words come from config/tour.yml, by the stop's id.
//
// Never on a phone: the server leaves it out for one it recognises, and this declines in a
// window too narrow for the sidebar and navbar it points at.
const COOKIE = "tour";
const WIDE_ENOUGH = "(min-width: 992px)";
// Long enough for the page's own controllers to have drawn what the stops point at -- the
// guide fetches its grid, the channel page restores its filters from the address.
const SETTLE = 800;
const TYPING = 90;
// The filter stop's run of years, and how long each one takes to light.
const FILTER_RUN = 4;
const FILTER_STEP = 220;

const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Shown at all, not merely present in the DOM: a collapsed sidebar or a hidden guide is
// not something to point at.
const visible = (element) => element && element.getClientRects().length > 0 && !element.closest("[hidden]");
const find = (selector) => {
  const element = document.querySelector(selector);
  return visible(element) ? element : null;
};

export default class extends Controller {
  static values = { config: Object };

  connect() {
    if (!window.matchMedia(WIDE_ENOUGH).matches) return this.end();

    const { pages } = this.configValue;
    const starting = new URLSearchParams(window.location.search).has("tour");
    this.page = starting ? pages[0] : this.readCookie();

    if (!this.page || !pages.includes(this.page)) return this.end();

    // Take Tour can be pressed anywhere; the tour starts where it starts.
    if (starting && !this.isOn(this.page)) return this.go(this.page);
    if (!this.isOn(this.page)) return this.end();

    if (starting) this.dropStartParam();
    this.writeCookie(this.page);
    this.settling = setTimeout(() => this.run(), SETTLE);
  }

  disconnect() {
    clearTimeout(this.settling);
    // A Turbo visit takes this page away mid-tour; that is a move, not the viewer quitting.
    this.moving = true;
    this.tour?.destroy();
    this.release();
  }

  // ---- running a page ----------------------------------------------------------------

  run() {
    const stops = this.stopsFor(this.page).filter((stop) => !stop.when || stop.when());
    if (stops.length === 0) return this.advance();

    this.stops = stops;
    this.tour = driver({
      steps: stops.map((stop) => this.step(stop)),
      popoverClass: "tour-popover",
      overlayOpacity: 0.65,
      stagePadding: 8,
      stageRadius: 8,
      smoothScroll: true,
      allowClose: true,
      // The page is being demonstrated, not used: a click on what is lit could navigate
      // away from under the tour.
      disableActiveInteraction: true,
      showButtons: ["next", "previous", "close"],
      nextBtnText: "Next",
      prevBtnText: "Back",
      doneBtnText: this.isLastPage ? "Enjoy" : "Next",
      onNextClick: () => (this.tour.isLastStep() ? this.advance() : this.tour.moveNext()),
      onDestroyed: () => {
        if (!this.moving) this.end();
      }
    });
    this.tour.drive();
  }

  // One stop as Driver.js wants it. Each visit to a stop gets its own token, and the
  // stop's demonstration checks it between moves, so leaving a stop halfway through its
  // typing or clicking stops it there rather than letting it carry on under the next one.
  step(stop) {
    const words = this.words(stop.id);

    return {
      element: stop.element,
      popover: {
        title: words.title,
        description: words.body,
        side: stop.side,
        onPopoverRender: stop.id === "finale" ? (popover) => this.addSignUp(popover) : undefined
      },
      onHighlighted: () => {
        const token = (this.token = Symbol(stop.id));
        stop.show?.(() => this.token === token);
      },
      onDeselected: () => {
        this.token = null;
        stop.leave?.();
      }
    };
  }

  get isLastPage() {
    const { pages } = this.configValue;
    return pages.indexOf(this.page) === pages.length - 1;
  }

  // On to the next page of the tour, or the end of it.
  advance() {
    const { pages } = this.configValue;
    const next = pages[pages.indexOf(this.page) + 1];

    this.moving = true;
    this.tour?.destroy();
    this.release();

    if (!next) return this.end();
    this.go(next);
  }

  go(page) {
    this.writeCookie(page);
    const path = this.configValue.paths[page];

    // /cable is its own layout with a player in it; a whole page load is the honest way in.
    if (page !== "cable" && window.Turbo) window.Turbo.visit(path);
    else window.location.assign(path);
  }

  end() {
    this.clearCookie();
    this.release();
    if (new URLSearchParams(window.location.search).has("tour")) this.dropStartParam();
  }

  isOn(page) {
    const { pathname, search } = window.location;
    const query = new URLSearchParams(search).get("query");
    const channel = this.configValue.paths.channel && new URL(this.configValue.paths.channel, window.location.origin).pathname;

    switch (page) {
      case "home": return pathname === "/" || pathname === "/lists";
      case "channel": return pathname === channel && !query;
      case "results": return pathname === channel && !!query;
      case "cable": return pathname === "/cable" || /^\/cable\/\d+/.test(pathname);
      default: return false;
    }
  }

  words(id) {
    const { text, signedIn } = this.configValue;
    return (!signedIn && text[`${id}_guest`]) || text[id] || {};
  }

  // ---- the stops ---------------------------------------------------------------------

  stopsFor(page) {
    switch (page) {
      case "home": return this.homeStops();
      case "channel": return this.channelStops();
      case "results": return this.resultStops();
      case "cable": return this.cableStops();
      default: return [];
    }
  }

  homeStops() {
    return [
      {
        id: "search",
        element: "#navbar-search",
        side: "bottom",
        when: () => find("#navbar-search"),
        show: (alive) => this.type(document.getElementById("navbar-search"), this.configValue.searchTerm, alive)
      },
      {
        // Opened here rather than trusted to still be open from the typing, and shut
        // here when the stop is left. The overlay's own dismissal listens for a click
        // outside the search box, and never hears one: Driver.js keeps clicks on its
        // buttons to itself, so without this the results sat over the rest of the tour.
        id: "results",
        element: () => document.querySelector('[data-list-search-target="results"]'),
        side: "bottom",
        when: () => find("#navbar-search") && this.configValue.searchTerm,
        show: async (alive) => {
          this.searchController()?.openOverlay();
          await pause(700);
          if (alive()) document.getElementById("navShowType")?.click();
        },
        leave: () => {
          this.searchController()?.hideResults();
          document.getElementById("navbar-search")?.blur();
        }
      },
      {
        id: "sidebar",
        element: "#sidebarChannelsPanel",
        side: "right",
        when: () => find("#sidebarChannelsPanel")
      },
      {
        id: "community",
        element: '[data-tour="community"]',
        side: "top",
        when: () => find('[data-tour="community"]')
      }
    ];
  }

  channelStops() {
    return [
      {
        // A run of years, the way a drag down the rail takes one: each year is painted as
        // it is reached and the whole run committed once at the end. A scripted click per
        // year commits every time -- Up Next re-picks, the address is rewritten, all
        // twelve hundred cards are walked -- which is what made this stop drag. Put back
        // to everything when the stop is left.
        id: "filters",
        element: '[data-tour="filters"]',
        side: "left",
        when: () => this.filterOptions().length > 0 && this.filterController(),
        show: async (alive) => {
          const filter = this.filterController();
          const options = this.filterOptions();
          // A third of the way in rather than from the top: the earliest years of a long
          // channel are the thinnest, and a run of empty-looking decades says little.
          const start = Math.min(Math.floor(options.length / 3), Math.max(options.length - FILTER_RUN, 0));
          const run = options.slice(start, start + FILTER_RUN);

          run[0].scrollIntoView({ block: "center", behavior: "smooth" });
          await pause(500);

          for (const option of run) {
            if (!alive()) return;
            filter.set(option.dataset.section, true);
            filter.paint();
            await pause(FILTER_STEP);
          }
          if (alive()) filter.commit();
        },
        leave: () => {
          const filter = this.filterController();
          if (!filter || filter.selected.size === 0) return;

          filter.selected.clear();
          filter.commit();
        }
      },
      {
        // Typed, not sent: the next page of the tour is this search already run.
        id: "channel_search",
        element: '[data-tour="channel-search"]',
        side: "bottom",
        when: () => find('[data-tour="channel-search"]') && this.configValue.pages.includes("results"),
        show: async (alive) => {
          const form = document.querySelector('[data-tour="channel-search"]');
          form.querySelector("button")?.click();
          await pause(400);
          if (alive()) this.type(form.querySelector("input[type=text], input:not([type])"), this.configValue.channelSearch, alive);
        }
      }
    ];
  }

  resultStops() {
    return [
      {
        id: "channel_result",
        element: () => this.firstCard(),
        side: "right",
        when: () => this.firstCard()
      },
      {
        id: "now_playing",
        element: "#nowPlayingContent",
        side: "right",
        when: () => find("#nowPlayingContent") && this.configValue.pages.includes("cable")
      }
    ];
  }

  cableStops() {
    return [
      {
        id: "cable",
        element: "#cinema-frames",
        side: "right",
        when: () => find("#cinema-frames")
      },
      {
        id: "guide",
        element: ".tvguide",
        side: "top",
        when: () => find(".tvguide")
      },
      {
        // The banner is hidden while the guide is up and fades when the pointer is still,
        // so the guide is put away and the banner held up for as long as this stop lasts.
        // One flip down, on the frame the page already warmed for it; the chrome is
        // replaced by the move, so the stop is lit again on the new banner.
        id: "hud",
        element: () => document.querySelector(".cable-hud__pad"),
        side: "bottom",
        when: () => document.querySelector(".cable-hud__pad"),
        show: async (alive) => {
          this.guideController()?.close();
          document.body.classList.add("tour-holding-hud");
          this.tour.refresh();
          if (this.flipped) return;

          await pause(1800);
          if (!alive()) return;
          this.flipped = true;
          document.addEventListener("cinema-navigation:moved", () => this.relightHud(), { once: true });
          document.querySelector(".cable-hud__key--down")?.click();
        },
        leave: () => document.body.classList.remove("tour-holding-hud")
      },
      { id: "finale" }
    ];
  }

  // The flip replaced the banner the HUD stop was lit on. Lit again on the new one, if the
  // viewer is still on that stop -- asked of the tour rather than of the stop's token,
  // which the move itself can outlive.
  relightHud() {
    const index = this.tour?.getActiveIndex();
    if (index === undefined || this.stops[index]?.id !== "hud") return;

    this.tour.moveTo(index);
  }

  // ---- what the stops work with -----------------------------------------------------

  async type(input, text, alive) {
    if (!input || !text) return;

    input.focus();
    input.value = "";
    for (const character of text) {
      if (!alive()) return;
      input.value += character;
      input.dispatchEvent(new Event("input", { bubbles: true }));
      await pause(TYPING);
    }
  }

  filterOptions() {
    return [...document.querySelectorAll('[data-tour="filters"] [data-section-filter-target="option"]')];
  }

  filterController() {
    const element = document.querySelector('[data-controller~="section-filter"]');
    return element && this.application.getControllerForElementAndIdentifier(element, "section-filter");
  }

  firstCard() {
    return [...document.querySelectorAll('[data-section-filter-target="card"], #list-entries > *')].find(visible) || null;
  }

  searchController() {
    const element = document.querySelector('[data-controller~="list-search"]');
    return element && this.application.getControllerForElementAndIdentifier(element, "list-search");
  }

  guideController() {
    const element = document.querySelector('[data-controller~="cable-guide"]');
    return element && this.application.getControllerForElementAndIdentifier(element, "cable-guide");
  }

  // The last stop's own way out for a guest: the tour's point, made once, as a button.
  addSignUp(popover) {
    if (this.configValue.signedIn) return;

    const link = document.createElement("a");
    link.href = this.configValue.paths.signUp;
    link.className = "tour-popover__sign-up";
    link.textContent = "Sign Up";
    link.addEventListener("click", () => this.end());
    popover.footerButtons.prepend(link);
  }

  // Whatever a stop left changed on the page, put back -- for a tour closed by its X or
  // Escape partway through a stop, which Driver.js does not always report as leaving it.
  release() {
    document.body.classList.remove("tour-holding-hud");
    this.searchController()?.hideResults();
  }

  // ---- the cookie --------------------------------------------------------------------

  readCookie() {
    return document.cookie.split("; ").find((pair) => pair.startsWith(`${COOKIE}=`))?.split("=")[1] || null;
  }

  // A session cookie: a tour abandoned by closing the browser should not be waiting for
  // them next week.
  writeCookie(page) {
    document.cookie = `${COOKIE}=${page}; path=/; samesite=lax`;
  }

  clearCookie() {
    document.cookie = `${COOKIE}=; max-age=0; path=/; samesite=lax`;
  }

  dropStartParam() {
    const url = new URL(window.location.href);
    url.searchParams.delete("tour");
    window.history.replaceState(window.history.state, "", url);
  }
}
