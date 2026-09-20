require 'rails_helper'

# The JavaScript has no browser-level test coverage, and both of the failure modes below
# are silent: a bare import that isn't pinned throws only in the browser console, and a
# method defined twice in a class body is quietly replaced by the later definition. These
# are cheap static guards for both.
RSpec.describe 'JavaScript modules' do
  JS_FILES = Rails.root.glob('app/javascript/**/*.js').freeze

  def relative(path) = path.relative_path_from(Rails.root).to_s

  describe 'import specifiers' do
    let(:importmap) do
      JSON.parse(Rails.application.importmap.to_json(resolver: ApplicationController.helpers))['imports']
    end

    it 'pins every bare specifier the app imports' do
      unresolved = JS_FILES.flat_map { |file|
        file.read.scan(/^\s*import\s+.*?from\s+["']([^"']+)["']/).flatten
            .reject { |spec| spec.start_with?('.', '/') }
            .reject { |spec| importmap.key?(spec) }
            .map { |spec| "#{relative(file)} imports #{spec}" }
      }

      expect(unresolved).to be_empty
    end
  end

  describe 'method definitions' do
    # `showErrorMessage` was defined twice in mobile_search_controller.js: a failed add
    # showed "No results found" instead of the error toast, because the later definition
    # won. Nothing surfaced it but reading the file.
    it 'defines each method once per file' do
      shadowed = JS_FILES.flat_map { |file|
        names = file.read.scan(/^  (\w+)\(/).flatten - %w[if for while switch catch constructor]
        names.tally.select { |_, count| count > 1 }
             .map { |name, count| "#{relative(file)}: #{name} defined #{count} times" }
      }

      expect(shadowed).to be_empty
    end
  end

  describe 'method calls within a file' do
    # `applyChrome`, `swap` and `swapInner` were deleted from cinema_navigation_controller
    # by a careless edit while the calls to them stayed. Nothing failed: the suite was
    # green, the static checks below passed -- they only look at what the *views* reference
    # -- and the page went on rendering. It broke only when somebody changed channel, at
    # which point the move died silently in a TypeError and the address bar simply did not
    # move. This is the check that would have caught it in the file it happened in.
    #
    # A mixin's methods count as defined on whatever mixes it in, and a handler assigned in
    # a constructor counts as defined too; the mixin file itself is skipped, because its
    # `this` is deliberately somebody else's object.
    BEHAVIOUR = Rails.root.join('app/javascript/services/tmdb_search_behavior.js')
    STIMULUS_BUILT_INS = %w[dispatch].freeze

    it 'calls only methods that exist' do
      mixin = BEHAVIOUR.read.scan(/^  (?:async )?(\w+)\(/).flatten

      missing = JS_FILES.reject { |file| file == BEHAVIOUR }.flat_map { |file|
        source = file.read
        defined = source.scan(/^  (?:async |get |static )?(\w+)\(/).flatten
        defined += source.scan(/this\.(\w+)\s*=[^=]/).flatten
        defined += mixin if source.include?('TmdbSearchBehavior')

        (source.scan(/\bthis\.(\w+)\(/).flatten.uniq - defined - STIMULUS_BUILT_INS)
          .map { |name| "#{relative(file)}: this.#{name}() is never defined" }
      }

      expect(missing).to be_empty
    end
  end

  describe 'stimulus actions in the views' do
    # `search#entries` was deleted from search_controller.js in 8803106, but the eight
    # data-action attributes pointing at it stayed in lists/show. Stimulus fails those
    # bindings silently apart from a console error, so nothing surfaced it.
    let(:controllers) do
      Rails.root.glob('app/javascript/controllers/*_controller.js').to_h { |file|
        [file.basename('_controller.js').to_s.tr('_', '-'), file]
      }
    end

    # `async` is part of the definition, not of the name: without it here an async handler
    # reads as a method the controller does not have, which is the opposite of the mistake
    # this is looking for.
    METHOD_DEFINITION = /^  (?:async\s+)?(\w+)\(/

    let(:mixin_methods) do
      Rails.root.join('app/javascript/services/tmdb_search_behavior.js').read.scan(METHOD_DEFINITION).flatten
    end

    # The two controllers that take their shared methods from the mixin at load time.
    MIXED_IN = %w[list-search mobile-search].freeze

    def methods_on(identifier, file)
      methods = file.read.scan(METHOD_DEFINITION).flatten
      methods += mixin_methods if MIXED_IN.include?(identifier)
      methods
    end

    it 'only references methods the controllers define' do
      dangling = Rails.root.glob('app/views/**/*.erb').flat_map { |view|
        view.read.each_line.with_index(1).flat_map { |line, number|
          next [] if line.lstrip.start_with?('<%#')

          line.scan(/(?:->|\b)([a-z0-9-]+)#(\w+)/).filter_map { |identifier, method|
            file = controllers[identifier]
            next if file.nil? || methods_on(identifier, file).include?(method)

            "#{relative(view)}:#{number} -> #{identifier}##{method}"
          }
        }
      }

      expect(dangling).to be_empty
    end

    # sort_controller declares no targets at all, yet a child-list row carried
    # data-sort-target="item" -- and child lists have no reorder endpoint, so the row was
    # never draggable in the first place. Stimulus ignores an undeclared target silently.
    it 'only references targets the controllers declare' do
      dangling = controllers.flat_map { |identifier, file|
        declared = file.read[/static targets = \[([^\]]*)\]/, 1].to_s.scan(/"(\w+)"/).flatten
        attribute = identifier.tr('-', '_')

        Rails.root.glob('app/views/**/*.erb').flat_map { |view|
          source = view.read
          used = source.scan(/data-#{identifier}-target=["'](\w+)["']/).flatten
          # Anchored: without it `expanding_search_target:` reads as a `search` target, and
          # every controller whose name ends in another's collects its targets.
          used += source.scan(/(?<![\w-])#{attribute}_target:\s*["'](\w+)["']/).flatten

          (used.uniq - declared).map { |target| "#{relative(view)} -> #{identifier} target '#{target}'" }
        }
      }

      expect(dangling).to be_empty
    end
  end

  # `{{#selected}}selected{{/selected}}` sat in attribute-name position on an <option>.
  # The browser parses <template> content as HTML long before mustache sees it, and an
  # unquoted `/` in a tag is taken for a self-closing marker and dropped -- so what
  # innerHTML handed mustache was `selected}}`, and it failed with "Unclosed section".
  # A mustache tag inside a tag is only safe inside a quoted attribute value.
  describe 'mustache templates' do
    TEMPLATE = /<template\b.*?<\/template>/m
    TAG = /<[a-zA-Z][^<>]*>/m
    QUOTED = /"[^"]*"|'[^']*'/

    it 'keeps every tag either an element of its own or a quoted attribute value' do
      exposed = Rails.root.glob('app/views/**/*.erb').flat_map { |view|
        source = view.read

        source.scan(TEMPLATE).flat_map { |template|
          template.scan(TAG).filter_map { |tag|
            next unless tag.gsub(QUOTED, '""').include?('{{')

            "#{relative(view)} -> #{tag.strip[0, 80]}"
          }
        }
      }

      expect(exposed).to be_empty
    end
  end

  # Clicking away used to empty the overlay as well as hide it, so returning to a query
  # still sitting in the search box showed nothing. Hiding and discarding are separate.
  describe 'dismissing the search overlay' do
    it 'hides without emptying' do
      behaviour = Rails.root.join('app/javascript/services/tmdb_search_behavior.js').read
      body = behaviour[/hideResults\(\) \{.*?\n  \},/m]

      expect(body).to include("classList.add('d-none')")
      expect(body).not_to include('innerHTML')
    end
  end

  # The overlay was left stuck open twice: once by a `{ once: true }` listener that a click
  # inside it spent, and once after a turbo stream render. Dismissal is armed for the
  # controller's whole life now rather than by whatever last drew the results.
  describe 'dismissing the search overlay' do
    let(:controller) { Rails.root.join('app/javascript/controllers/list_search_controller.js').read }

    it 'arms the outside click in connect, not only in a render' do
      connect = controller[/  connect\(\) \{.*?\n  \}/m]

      expect(connect).to include("document.addEventListener('click', this.boundClickOutside)")
    end

    it 'never arms it for a single click' do
      expect(controller).not_to match(/addEventListener\('click', this\.boundClickOutside, \{ once: true \}\)/)
    end

    it 'survives a stale element and an exception' do
      handler = controller[/  dismissOnOutsideClick\(event\) \{.*?\n  \}/m]

      expect(handler).to include('document.contains(this.element)')
      expect(handler).to include('catch')
    end
  end

  # A refusal from the add endpoints comes back as a flash stream. Checking the status and
  # throwing before reading it left the button saying "Failed" with the reason unread.
  describe 'reporting an add that was refused' do
    it 'renders the response before deciding it failed' do
      controller = Rails.root.join('app/javascript/controllers/list_search_controller.js').read
      applied = controller[/  applyStream\(response\) \{.*?\n  \}/m]

      expect(applied).to include('renderStreamMessage')
      expect(controller).to include('.then(response => this.applyStream(response))')
    end
  end

  # Up Next reads the cards on the page. A channel inside another channel is one of them,
  # and has no completion record to read -- excluding it made a channel of channels suggest
  # nothing at all.
  describe 'what Up Next will suggest' do
    it 'counts a channel card as something to watch' do
      controller = Rails.root.join('app/javascript/controllers/randomize_controller.js').read
      eligible = controller[/  eligible\(\) \{.*?\n  \}/m]

      expect(eligible).to include('channel-card')
      expect(eligible).to include('.completion-status .fa-regular.fa-eye')
    end
  end

  # Two filter axes on one page: what an entry is, and which channel it came from. They are
  # ANDed, which means the section axis can no longer decide visibility on its own -- a
  # section whose every card was hidden by the source axis has to go too.
  describe 'the two filter axes' do
    let(:controller) { Rails.root.join('app/javascript/controllers/section_filter_controller.js').read }

    it 'hides cards by source and sections by section' do
      paint = controller[/  paint\(\) \{.*?\n  \}/m]

      expect(paint).to include('this.sources.has(card.dataset.source)')
      expect(paint).to include('this.selected.has(section.dataset.section)')
    end

    it 'drops a section the source axis emptied' do
      expect(controller).to include('this.emptied(section)')
    end

    it 'carries both in the url' do
      written = controller[/  writeUrl\(\) \{.*?\n  \}/m]

      expect(written).to include('PARAM')
      expect(written).to include('SOURCE_PARAM')
    end
  end

  describe 'the shared search behaviour' do
    let(:shared) { Rails.root.join('app/javascript/services/tmdb_search_behavior.js') }
    let(:controllers) do
      %w[list_search mobile_shell].map { |name| Rails.root.join("app/javascript/controllers/#{name}_controller.js") }
    end

    # These six were byte-identical copies in both controllers before they were extracted.
    # The phone side of it is mobile_shell now -- the bar it lives on does the filtering and
    # the menu as well as the search -- but the rule is the same: one copy, mixed in.
    SHARED_METHODS = %w[tmdbSearch tmdbShow showOverlay handleClickOutside hideResults showToast].freeze

    it 'holds the only copy of the methods both controllers share' do
      SHARED_METHODS.each do |method|
        expect(shared.read).to match(/^  #{method}\(/), "#{method} is missing from the shared module"

        controllers.each do |controller|
          expect(controller.read).not_to match(/^  #{method}\(/),
                                          "#{relative(controller)} has its own copy of #{method} again"
        end
      end
    end

    it 'mixes the behaviour into both controllers' do
      controllers.each do |controller|
        source = controller.read
        expect(source).to include('import { TmdbSearchBehavior } from "services/tmdb_search_behavior"')
        expect(source).to match(/Object\.assign\(\w+\.prototype, TmdbSearchBehavior\)/)
      end
    end
  end

  # The warmed spare is quietened by being asked, and the asking can fail. Commit 4c5d182
  # measured a vidsrc player reporting "fourteen times in seventy seconds and none at all
  # in sixty" -- the same code, the same entry -- and a player that never speaks can never
  # be told anything. VIDSRC.md §6a has the rest: such a frame is not idling but playing,
  # and drifts along with the clock. So a second film could run behind the first for the
  # whole of it, on a coin toss nobody sees, which is two hardware decoders where there
  # should be one.
  #
  # The deadline is what stops that. None of it can fail visibly -- a spare nobody can hear
  # is exactly the thing that went unnoticed for months -- so each property is pinned here.
  describe 'the deadline on a spare that will not stop' do
    let(:controller) { Rails.root.join('app/javascript/controllers/cinema_navigation_controller.js').read }

    it 'arms a deadline whenever it builds a spare frame' do
      built = controller[/  buildSpareFrame\(role, incoming, adapter\) \{.*?\n  \}/m]

      expect(built).to include('setTimeout(() => this.dropIfStillPlaying(role), STOP_DEADLINE)')
    end

    # Silence is not stopping. This is the whole point: the frame that caused the trouble
    # is the one that never said anything, and "no news is good news" is what would put it
    # straight back.
    it 'keeps the frame only when the spare both spoke and then settled' do
      verdict = controller[/  dropIfStillPlaying\(role\) \{.*?\n  \}/m]

      expect(verdict).to include('const spoke = spare.movedAt !== undefined')
      expect(verdict).to include('const settled = spoke && Date.now() - spare.movedAt >= QUIET_ENOUGH')
      expect(verdict).to include('if (settled) return')
    end

    # Only the frame is given up. The page fetched for that direction is what makes the
    # move cost no request, and throwing it away as well would turn a quietening problem
    # into a slower channel change.
    it 'gives up the frame but keeps the page already fetched' do
      verdict = controller[/  dropIfStillPlaying\(role\) \{.*?\n  \}/m]

      expect(verdict).to include("document.getElementById(FRAMES[role])?.remove()")
      expect(verdict).not_to include('delete this.spares[role]')
    end

    # A timer left armed against a frame that has since become the live one would tear down
    # the film being watched.
    it 'disarms the deadline when the spare is adopted or discarded' do
      adopted = controller[/  adoptSpare\(incoming\) \{.*?\n  \}/m]
      discarded = controller[/  discardSpares\(\) \{.*?\n  \}/m]

      expect(adopted).to include('clearTimeout(spare.stopTimer)')
      expect(discarded).to include('clearTimeout(this.spares[role].stopTimer)')
    end

    # The quiet period has to be longer than the gap between two reports, or a spare caught
    # between them reads as stopped and keeps a frame it should have lost.
    it 'waits longer than the gap between two of the player\'s reports' do
      quiet = controller[/const QUIET_ENOUGH = (\d+)/, 1].to_i
      deadline = controller[/const STOP_DEADLINE = (\d+)/, 1].to_i

      expect(quiet).to be > 5000
      expect(deadline).to be > quiet
    end
  end

  # Warming a player of our own is a different thing from warming an embed, and the
  # difference is the whole reason it is allowed at all.
  #
  # An embed has to be started and then asked to stop, and the asking can fail -- which is
  # what STOP_DEADLINE above exists for. A <video> we own is never started: `preload` fills
  # its buffer and nothing plays, so there is no second decoder and nothing that can refuse
  # to stop. Every assertion here pins one half of "buffered, never played", because a
  # single `play()` slipped into this path would quietly reintroduce the fault the deadline
  # was written to catch.
  describe 'warming a player the app owns' do
    let(:controller) { Rails.root.join('app/javascript/controllers/cinema_navigation_controller.js').read }
    let(:warmed) { controller[/  buildSpareVideo\(role, incoming\) \{.*?\n  \}/m] }

    it 'fills a buffer rather than starting a player' do
      expect(warmed).to include('video.preload = "auto"')
      expect(warmed).not_to include('.play()')
      expect(warmed).not_to include('autoplay')
    end

    it 'keeps it silent while it warms' do
      expect(warmed).to include('video.muted = true')
    end

    # The address it would be pointed at is one only the service worker answers. On a page
    # whose own player is an embed nothing has registered it, and the spare would 404.
    it 'declines when no service worker is in control' do
      expect(warmed).to include('if (!navigator.serviceWorker?.controller) return')
    end

    # No deadline, because there is nothing to stop. Arming one here would mean a timer
    # tearing down a frame for failing a test it was never subject to.
    it 'arms no stop deadline, having nothing to stop' do
      expect(warmed).not_to include('STOP_DEADLINE')
      expect(warmed).not_to include('stopTimer')
    end

    # A <video> carries its address in a data attribute until it is handed one, so matching
    # a spare to a move on `src` alone would never find it.
    it 'matches a spare by the address it carries, whichever way it carries it' do
      adopt = controller[/  adoptSpare\(incoming\) \{.*?\n  \}/m]

      expect(adopt).to include('this.addressOf(held) === address')
    end

    # Promotion is the first time it plays at all, so it is a start rather than a resume.
    it 'starts it, unmuted, when it is promoted' do
      start = controller[/  startWarmedVideo\(video, incoming\) \{.*?\n  \}/m]

      expect(start).to include('video.muted = false')
      expect(start).to include('video.play()')
      expect(start).to include('incoming.dataset.nativePlayerStartValue')
    end
  end
end
