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

  describe 'stimulus actions in the views' do
    # `search#entries` was deleted from search_controller.js in 8803106, but the eight
    # data-action attributes pointing at it stayed in lists/show. Stimulus fails those
    # bindings silently apart from a console error, so nothing surfaced it.
    let(:controllers) do
      Rails.root.glob('app/javascript/controllers/*_controller.js').to_h { |file|
        [file.basename('_controller.js').to_s.tr('_', '-'), file]
      }
    end

    let(:mixin_methods) do
      Rails.root.join('app/javascript/services/tmdb_search_behavior.js').read.scan(/^  (\w+)\(/).flatten
    end

    # The two controllers that take their shared methods from the mixin at load time.
    MIXED_IN = %w[list-search mobile-search].freeze

    def methods_on(identifier, file)
      methods = file.read.scan(/^  (\w+)\(/).flatten
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

  describe 'the shared search behaviour' do
    let(:shared) { Rails.root.join('app/javascript/services/tmdb_search_behavior.js') }
    let(:controllers) do
      %w[list_search mobile_search].map { |name| Rails.root.join("app/javascript/controllers/#{name}_controller.js") }
    end

    # These six were byte-identical copies in both controllers before they were extracted.
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
end
