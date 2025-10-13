# 🚀 How to Watch - Refactoring & Improvement Roadmap

**Last Updated:** October 13, 2025
**Context:** This Rails app manages user watchlists with video streaming sources. Users can track progress through lists, with support for movies, TV series, and anime.

---

## 📋 **Priority 1: High Impact, Low Effort (Do First)**

### ✅ 1. Add Database Indexes

**Why:** Massive performance gains with minimal code changes. Current queries on `user_list_positions`, `entries`, and `user_entries` are slow without indexes.

**Files to Create:**
```bash
rails generate migration AddPerformanceIndexes
```

**Migration Content:**
```ruby
# db/migrate/XXXXXX_add_performance_indexes.rb
class AddPerformanceIndexes < ActiveRecord::Migration[7.0]
  def change
    # UserListPosition queries (critical for current_entry lookups)
    add_index :user_list_positions, [:list_id, :user_id], unique: true,
              name: 'index_positions_on_list_and_user'
    add_index :user_list_positions, :updated_at

    # Entry queries (critical for position-based lookups)
    add_index :entries, [:list_id, :position], name: 'index_entries_on_list_and_position'
    add_index :entries, :media
    add_index :entries, :imdb

    # UserEntry queries (critical for completion tracking)
    add_index :user_entries, [:user_id, :completed]
    add_index :user_entries, [:entry_id, :user_id], unique: true,
              name: 'index_user_entries_unique'
    add_index :user_entries, :completed_at
    add_index :user_entries, :last_watched_at

    # List queries (critical for index page)
    add_index :lists, [:user_id, :private]
    add_index :lists, :created_at
    add_index :lists, :ordered

    # Subscription queries
    add_index :subscriptions, [:user_id, :list_id], unique: true,
              name: 'index_subscriptions_unique'

    # Subentry queries (for series/anime)
    add_index :subentries, [:entry_id, :season, :episode],
              name: 'index_subentries_for_lookup'
  end
end
```

**Test Impact:**
```bash
rails db:migrate
# Monitor query times in development.log before/after
```

---

### ✅ 2. Fix N+1 Queries in List Index

**Problem:** `app/views/lists/index.html.erb` calls `list.current_entry(current_user)` for each list, causing N+1 queries.

**File to Edit:** `app/controllers/lists_controller.rb`

**Current Code (Lines 28-38):**
```ruby
@your_lists = current_user.lists.order(created_at: :desc).includes(:entries, :user)
```

**Replace With:**
```ruby
# Load user_list_positions eagerly for all lists
@your_lists = current_user.lists
                          .includes(:entries, :user, :user_list_positions)
                          .order(created_at: :desc)

# Same for recently_watched_lists (lines 33-38)
@recently_watched_lists = List.joins(entries: :user_entries)
                              .includes(:entries, :user, :user_list_positions)
                              .where(user_entries: { user: current_user, completed: true })
                              .group('lists.id')
                              .order('MAX(user_entries.completed_at) DESC')
                              .limit(20)

# Same for community_lists (lines 42-62)
# Add .includes(:user_list_positions) to both admin and non-admin queries
```

**Verify Fix:**
```bash
# Install bullet gem first (see setup section below)
# Check development.log - should see queries reduced from ~50+ to ~5
```

---

### ✅ 3. Add Basic Error Handling

**Problem:** Nil sources cause blank iframes, API failures crash, no user feedback.

**Step 1:** Create error classes
```ruby
# app/errors/application_errors.rb (NEW FILE)
module ApplicationErrors
  class NoSourceAvailableError < StandardError; end
  class ApiTimeoutError < StandardError; end
  class InvalidPositionError < StandardError; end
end
```

**Step 2:** Update `app/controllers/application_controller.rb`
```ruby
class ApplicationController < ActionController::Base
  rescue_from ApplicationErrors::NoSourceAvailableError do |e|
    flash[:alert] = "This entry has no watchable source available"
    redirect_to lists_path
  end

  rescue_from ApplicationErrors::ApiTimeoutError do |e|
    flash[:alert] = "External service timeout. Please try again later."
    redirect_back(fallback_location: lists_path)
  end

  rescue_from ApplicationErrors::InvalidPositionError do |e|
    flash[:alert] = "Invalid list position. Redirecting to list view."
    redirect_to lists_path
  end
end
```

**Step 3:** Update `app/models/list.rb` (around line 197)
```ruby
def current_entry_for_user(user)
  # ... existing code ...
  if entry.nil? && entries.exists?
    # ... existing fallback code ...
    raise ApplicationErrors::InvalidPositionError if entry.nil?
  end
  entry
end
```

---

### ✅ 4. Extract Common View Partials

**Problem:** Duplicate code across 3 list card sections in `app/views/lists/index.html.erb`

**Step 1:** Create partial
```erb
<%# app/views/lists/_list_card.html.erb (NEW FILE) %>
<% current_entry = list.current_entry(current_user) %>
<div class="list-card">
  <% if current_entry %>
    <%= link_to watch_entry_path(current_entry), class: "text-decoration-none" do %>
      <div class="list-card-poster">
        <%= entry_poster_image_tag(current_entry, class: 'list-poster-img', alt: list.name) %>
        <div class="list-card-overlay">
          <i class="fa-solid fa-play fa-3x"></i>
        </div>
      </div>
    <% end %>
  <% else %>
    <%= link_to list_path(list), class: "text-decoration-none" do %>
      <div class="list-card-poster">
        <img src="/images/please_stand_by.png" alt="<%= list.name %>" class="list-poster-img">
        <div class="list-card-overlay">
          <i class="fa-solid fa-play fa-3x"></i>
        </div>
      </div>
    <% end %>
  <% end %>

  <%= link_to list_path(list), class: "text-decoration-none list-info-link" do %>
    <div class="list-card-info">
      <div class="list-card-text">
        <p class="list-card-name"><%= list.name %></p>
        <p class="list-card-meta">
          <%= yield :meta_text %>
        </p>
      </div>
      <i class="fa-solid fa-list list-info-icon"></i>
    </div>
  <% end %>
</div>
```

**Step 2:** Replace in `app/views/lists/index.html.erb`
```erb
<%# Line 7-34: Replace entire loop with %>
<% @recently_watched_lists.first(10).each do |list| %>
  <%= render 'list_card', list: list do %>
    <%= current_entry ? current_entry.name : pluralize(list.entries.count, 'entry') %>
  <% end %>
<% end %>

<%# Repeat for @your_lists and @community_lists %>
```

---

## 📋 **Priority 2: High Impact, Medium Effort**

### ⏳ 5. Create PositionService

**Why:** Position logic is scattered across `List`, `UserListPosition`, and controllers. Centralize it.

**Create:** `app/services/position_service.rb` (NEW FILE)
```ruby
class PositionService
  attr_reader :user, :list

  def initialize(user, list)
    @user = user
    @list = list
  end

  # Main entry point - replaces List#current_entry
  def current_entry
    return nil unless user && list.persisted?

    if list.ordered?
      ordered_current_entry
    else
      unordered_current_entry
    end
  end

  # Advance to next entry (ordered lists)
  def advance_to_next!
    return unless list.ordered?

    next_entry = list.entries.where('position > ?', user_position.current_position)
                    .order(:position)
                    .first

    if next_entry
      user_position.update!(current_position: next_entry.position)
      next_entry
    else
      current_entry # Stay at end
    end
  end

  # Pick random incomplete (unordered lists)
  def shuffle_to_random!
    return unless !list.ordered?

    random_entry = list.find_random_incomplete_entry_for_user(user)
    if random_entry
      user_position.update!(current_position: random_entry.position)
      random_entry
    else
      current_entry
    end
  end

  # Set to specific entry
  def update_to_entry!(entry)
    raise ArgumentError unless entry.list_id == list.id
    user_position.update!(current_position: entry.position)
    entry
  end

  private

  def ordered_current_entry
    entry = entry_at_position(user_position.current_position)
    entry || fix_invalid_position!
  end

  def unordered_current_entry
    # Always return random incomplete for unordered
    list.find_random_incomplete_entry_for_user(user) ||
      entry_at_position(user_position.current_position)
  end

  def entry_at_position(pos)
    list.entries.find_by(position: pos)
  end

  def fix_invalid_position!
    # Find next valid entry or first entry
    entry = list.entries.where('position >= ?', user_position.current_position)
                .order(:position)
                .first
    entry ||= list.entries.order(:position).first

    if entry
      user_position.update!(current_position: entry.position)
      entry
    else
      raise ApplicationErrors::InvalidPositionError
    end
  end

  def user_position
    @user_position ||= list.position_for_user(user)
  end
end
```

**Update:** `app/models/list.rb` (line 199)
```ruby
def current_entry(user)
  PositionService.new(user, self).current_entry
end
```

**Update Controllers:** Replace direct position manipulation with service calls
- `app/controllers/entries_controller.rb` (lines 349-372, complete action)
- `app/controllers/entries_controller.rb` (lines 264-289, increment_current)
- `app/controllers/entries_controller.rb` (lines 211-236, decrement_current)

---

### ⏳ 6. Create SourceUrlBuilder

**Why:** Source URL generation is complex, especially for anime. Centralize and simplify.

**Create:** `app/services/source_url_builder.rb` (NEW FILE)
```ruby
class SourceUrlBuilder
  attr_reader :entry, :subentry, :preferred_source, :autoplay

  def initialize(entry, subentry: nil, preferred_source: nil, autoplay: false)
    @entry = entry
    @subentry = subentry || entry.current
    @preferred_source = preferred_source || entry.preferred_source || entry.list&.preferred_source || 1
    @autoplay = autoplay
  end

  def build
    validate_sources!

    url = case entry.media
          when 'anime' then build_anime_url
          when 'series' then build_series_url
          when 'movie', 'fanedit' then build_movie_url
          when 'episode' then build_episode_url
          else raise "Unknown media type: #{entry.media}"
          end

    add_autoplay_param(url)
  end

  def self.for_watch_view(entry)
    new(entry, autoplay: entry.list.auto_play?).build
  end

  private

  def validate_sources!
    return if primary_source.present? || fallback_source.present?
    raise ApplicationErrors::NoSourceAvailableError, "No sources for entry #{entry.id}"
  end

  def build_anime_url
    return subentry.source if subentry&.source.present?

    # Anime uses absolute episode numbers
    if preferred_source == 2
      "https://v2.vidsrc.me/embed/#{entry.imdb}/#{subentry.season}-#{subentry.episode}"
    else
      absolute_ep = subentry&.calculate_absolute_episode_number || 1
      "https://vidsrc.cc/v2/embed/anime/#{entry.imdb}/#{absolute_ep}/sub"
    end
  end

  def build_series_url
    return subentry.source if subentry&.source.present?
    "#{primary_source}/#{subentry.season}-#{subentry.episode}"
  end

  def build_movie_url
    primary_source
  end

  def build_episode_url
    primary_source
  end

  def primary_source
    @primary_source ||= preferred_source == 2 ? entry.source_two : entry.source
  end

  def fallback_source
    @fallback_source ||= preferred_source == 2 ? entry.source : entry.source_two
  end

  def add_autoplay_param(url)
    return url unless url.present?
    separator = url.include?('?') ? '&' : '?'
    "#{url}#{separator}autoplay=#{autoplay ? '1' : '0'}"
  end
end
```

**Update:** `app/views/entries/watch.html.erb` (lines 33-57)
```erb
<iframe id="cinema"
    src="<%= SourceUrlBuilder.for_watch_view(@entry) %>"
    ...>
</iframe>
```

**Benefits:** Can now easily add new video sources, test URL generation, handle errors.

---

### ⏳ 7. Add Caching Layer

**Why:** List index and current_entry calculations are expensive and repeat frequently.

**Install Redis:**
```bash
# Add to Gemfile
gem 'redis', '~> 5.0'

# config/environments/development.rb & production.rb
config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'] }
```

**Update:** `app/models/list.rb` (around line 199)
```ruby
def current_entry(user)
  return nil unless user && persisted?

  # Cache key includes updated_at to auto-invalidate on list changes
  cache_key = ['list_current_entry', id, user.id, ordered?, updated_at.to_i]

  Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
    PositionService.new(user, self).current_entry
  end
end
```

**Update:** `app/controllers/lists_controller.rb` (line 33)
```ruby
@recently_watched_lists = Rails.cache.fetch(['recently_watched', current_user.id], expires_in: 1.hour) do
  List.joins(entries: :user_entries)
      .includes(:entries, :user, :user_list_positions)
      # ... rest of query
end
```

**Cache Invalidation:** Add to models that affect lists
```ruby
# app/models/user_list_position.rb
after_save :clear_current_entry_cache

private
def clear_current_entry_cache
  Rails.cache.delete(['list_current_entry', list_id, user_id, list.ordered?, list.updated_at.to_i])
end
```

---

### ⏳ 8. Add Integration Tests

**Why:** Core flows (watch, complete, navigate) have no test coverage. Critical for refactoring safely.

**Setup:**
```bash
# Add to Gemfile
group :test do
  gem 'rspec-rails', '~> 6.0'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'shoulda-matchers'
  gem 'database_cleaner-active_record'
end

rails generate rspec:install
```

**Create:** `spec/requests/watch_flow_spec.rb` (NEW FILE)
```ruby
require 'rails_helper'

RSpec.describe "Watch Flow", type: :request do
  let(:user) { create(:user) }
  let(:list) { create(:list, :ordered, user: user) }
  let!(:entry1) { create(:entry, list: list, position: 1) }
  let!(:entry2) { create(:entry, list: list, position: 2) }

  before { sign_in user }

  describe "watching an entry" do
    it "sets user position to that entry" do
      get watch_entry_path(entry1)

      position = list.position_for_user(user)
      expect(position.current_position).to eq(1)
    end

    it "shows nil source error when source is missing" do
      entry1.update!(source: nil, source_two: nil)

      get watch_entry_path(entry1)

      expect(response).to redirect_to(list_path(list))
      expect(flash[:alert]).to match(/no.*source/i)
    end
  end

  describe "completing an entry" do
    it "advances position to next entry" do
      get watch_entry_path(entry1)
      get complete_entry_path(entry1)

      position = list.position_for_user(user)
      expect(position.current_position).to eq(2)
    end

    it "marks entry as completed" do
      get complete_entry_path(entry1)

      expect(entry1.completed_by?(user)).to be true
    end
  end

  describe "navigating entries" do
    before { get watch_entry_path(entry1) }

    it "increments to next entry" do
      get increment_current_entry_path(entry1, mode: 'watch')

      expect(response).to redirect_to(watch_entry_path(entry2))
    end

    it "decrements to previous entry" do
      get watch_entry_path(entry2)
      get decrement_current_entry_path(entry2, mode: 'watch')

      expect(response).to redirect_to(watch_entry_path(entry1))
    end
  end
end
```

**Create Factories:** `spec/factories/` (NEW DIRECTORY)
```ruby
# spec/factories/users.rb
FactoryBot.define do
  factory :user do
    email { Faker::Internet.email }
    password { 'password123' }
    admin { false }
  end
end

# spec/factories/lists.rb
FactoryBot.define do
  factory :list do
    name { Faker::Movie.title }
    user
    ordered { true }
    private { false }

    trait :ordered do
      ordered { true }
    end

    trait :unordered do
      ordered { false }
    end
  end
end

# spec/factories/entries.rb
FactoryBot.define do
  factory :entry do
    name { Faker::Movie.title }
    media { 'movie' }
    source { 'https://vidsrc.cc/v3/embed/movie/tt1234567' }
    list
    position { 1 }
  end
end
```

**Run Tests:**
```bash
bundle exec rspec spec/requests/watch_flow_spec.rb
```

---

## 📋 **Priority 3: Medium Impact, High Effort (Do Later)**

### 🔄 9. Background Jobs for API Calls

**Why:** OMDB/TMDB API calls block user requests. Can take 5-10 seconds.

**Setup Solid Queue** (Rails 7.1+):
```bash
# Gemfile
gem 'solid_queue'

rails generate solid_queue:install
rails db:migrate
```

**Create:** `app/jobs/fetch_series_episodes_job.rb` (NEW FILE)
```ruby
class FetchSeriesEpisodesJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.seconds, attempts: 3

  def perform(entry_id)
    entry = Entry.find(entry_id)

    begin
      OmdbApi.get_series_episodes(entry)

      # Broadcast success via Turbo Stream
      broadcast_episodes_loaded(entry)
    rescue StandardError => e
      Rails.logger.error "Failed to fetch episodes for entry #{entry_id}: #{e.message}"
      broadcast_episodes_failed(entry)
    end
  end

  private

  def broadcast_episodes_loaded(entry)
    # Use Turbo Streams to update UI when complete
  end

  def broadcast_episodes_failed(entry)
    # Show error message to user
  end
end
```

**Update:** `app/controllers/entries_controller.rb` (line 52)
```ruby
# OLD:
OmdbApi.get_series_episodes(@entry)

# NEW:
FetchSeriesEpisodesJob.perform_later(@entry.id)
flash[:notice] = "#{@entry.name} added! Episodes loading in background..."
```

**Same for:** Trailer fetching, image repair, poster migration

---

### 🔄 10. Add Authorization Layer (Pundit)

**Setup:**
```bash
# Gemfile
gem 'pundit'

bundle install
rails generate pundit:install
```

**Create:** `app/policies/entry_policy.rb` (NEW FILE)
```ruby
class EntryPolicy < ApplicationPolicy
  def watch?
    user.present? && can_access_list?
  end

  def edit?
    user&.can_edit_entry?(record)
  end

  def destroy?
    edit?
  end

  private

  def can_access_list?
    record.list.public? ||
    user.subscribed_to?(record.list) ||
    user.owns?(record.list) ||
    user.admin?
  end
end
```

**Update:** `app/controllers/entries_controller.rb` (add before watch action)
```ruby
before_action :authorize_entry, only: [:watch, :edit, :update, :destroy]

private

def authorize_entry
  authorize @entry
end
```

**Same for:** `ListPolicy`, `UserPolicy`

---

## 🛠️ **Setup & Tools**

### Install Performance Monitoring Tools

**Add to Gemfile (development group):**
```ruby
group :development do
  gem 'bullet'                    # Detect N+1 queries
  gem 'rack-mini-profiler'        # Request profiling
  gem 'memory_profiler'           # Memory usage
  gem 'derailed_benchmarks'       # Performance benchmarking
  gem 'rails_best_practices'      # Code analysis
end
```

**Configure Bullet** (`config/environments/development.rb`):
```ruby
config.after_initialize do
  Bullet.enable = true
  Bullet.alert = true
  Bullet.bullet_logger = true
  Bullet.console = true
  Bullet.rails_logger = true
  Bullet.add_footer = true
end
```

**Run Analysis:**
```bash
bundle exec rails_best_practices .
bundle exec derailed bundle:mem
```

---

## 📝 **Context for Future AI Agents**

### Key Architecture Decisions

1. **User-Level Positions:** We use `UserListPosition` (not list-level `current`). Each user has their own position per list.

2. **Ordered vs Unordered Lists:**
   - Ordered: `current_entry` returns specific position
   - Unordered: `current_entry` returns random incomplete entry (changes each page load)

3. **Video Sources:**
   - `source` = primary (usually vidsrc.cc)
   - `source_two` = secondary (usually vidsrc.me)
   - Anime requires special handling: absolute episode numbers + `/sub` suffix

4. **Series/Anime Structure:**
   - `Entry` = series container
   - `Subentry` = individual episodes
   - `Entry.current` = current subentry being watched

5. **Completion Tracking:**
   - `UserEntry` tracks per-user completion
   - Completing an entry advances position to next

### Common Gotchas

- **Position Gaps:** Lists may have positions [2, 5, 7] (not sequential). Always handle missing positions.
- **Nil Sources:** Both `source` and `source_two` can be nil. Must check both and provide fallback.
- **Turbo Drive:** Disabled on watch page (`data-turbo="false"`) due to iframe issues.
- **N+1 Queries:** Always include `user_list_positions` when loading lists for current_entry.
- **Anime URLs:** Must end with `/sub`, use absolute episode numbers, not season-based.

### File Structure Guide

**Models:**
- `app/models/list.rb` - List management, position logic (TO BE REFACTORED)
- `app/models/entry.rb` - Entry/video management
- `app/models/user_list_position.rb` - User's position in each list
- `app/models/user_entry.rb` - User's completion status per entry
- `app/models/subentry.rb` - Episodes for series/anime

**Controllers:**
- `app/controllers/lists_controller.rb` - List CRUD, index page
- `app/controllers/entries_controller.rb` - Entry CRUD, watch page, navigation

**Views:**
- `app/views/lists/index.html.erb` - Main dashboard (3 horizontal scrolling rows)
- `app/views/entries/watch.html.erb` - Video player page
- `app/views/entries/_entry_*.html.erb` - Different entry card types
- `app/views/shared/_sidebar.html.erb` - Left sidebar with "Now Playing"

**Services (TO BE CREATED):**
- `app/services/position_service.rb` - Position management
- `app/services/source_url_builder.rb` - Video URL generation

### Testing Priority

1. Position advancement (most complex logic)
2. Source URL generation (critical path, anime edge cases)
3. Completion flow (user-facing, data integrity)
4. Ordered vs unordered list behavior
5. Nil handling (positions, sources, entries)

---

## 📊 **Success Metrics**

Track these after each improvement:

- **Page Load Time:** Target < 200ms for list index
- **Database Queries:** Target < 10 queries per page
- **Test Coverage:** Target > 80% for models, > 60% for controllers
- **N+1 Queries:** Zero in production (use Bullet)
- **Error Rate:** < 0.1% of requests
- **Cache Hit Rate:** > 80% for current_entry lookups

---

## 🎯 **Quick Start Checklist**

When starting a refactoring session:

1. ✅ Read this file completely
2. ✅ Run `git status` to see current changes
3. ✅ Check `development.log` for slow queries
4. ✅ Run `bundle exec bullet` to find N+1 queries
5. ✅ Pick ONE task from Priority 1
6. ✅ Create a new branch: `git checkout -b refactor/task-name`
7. ✅ Make changes, test thoroughly
8. ✅ Run tests: `bundle exec rspec` (when tests exist)
9. ✅ Check for new linter errors
10. ✅ Commit with descriptive message

---

**Questions?** Check:
- Recent git history: `git log --oneline -20`
- Database schema: `db/schema.rb`
- Routes: `rails routes | grep <resource>`
- Model relationships: Check `has_many`/`belongs_to` in models

**Last Major Changes:**
- Oct 13, 2025: Refactored list index to Netflix-style layout
- Oct 13, 2025: Switched to user-level positions (removed list-level current)
- Oct 13, 2025: Added dark/light mode support
- Oct 13, 2025: Fixed anime source URL generation (absolute episodes + /sub)
- Oct 13, 2025: Added auto-position fixing for invalid positions
