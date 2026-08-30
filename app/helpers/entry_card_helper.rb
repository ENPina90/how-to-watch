# frozen_string_literal: true

module EntryCardHelper
  # Runs of whitespace *between tags* carry no meaning in the card markup: the two
  # containers that hold siblings side by side (`.card-menu`, `.card-details`) are flex,
  # and flex drops whitespace-only text nodes. Text inside a tag is left alone, so titles
  # and plots are untouched.
  BETWEEN_TAGS = />[\s]+</
  private_constant :BETWEEN_TAGS

  # Renders one entry card with the template's indentation stripped out of the response.
  #
  # ERB emits the leading whitespace of every line verbatim. That is invisible on a page
  # with one card and 604 KB on a page with 1,203 of them -- 16% of the card bytes, more
  # than the plot, the trailer link and the whole action menu put together. Collapsing it
  # at render time keeps the templates readable, which the alternative (writing the
  # partials flat against the left margin) would not.
  #
  # Only card partials go through here. They contain no <pre>, <textarea> or <script>,
  # where whitespace would be significant -- `spec/requests/list_show_payload_spec.rb`
  # fails if one appears.
  # Where a card's play link goes. A page that borrows entries from the channels inside it
  # sends the channel along, so the watch page stays on the channel you were looking at
  # rather than dropping you into the one the entry happens to live in. Nothing is added
  # when the entry is already at home: the plain path is the common one.
  def watch_path_for(entry, viewing: nil)
    return watch_entry_path(entry) if viewing.nil? || entry.list_id == viewing.id

    watch_entry_path(entry, channel: viewing.id)
  end

  # A card for an entry the page borrowed from a channel inside this one wears the name of
  # the channel it actually lives in. In the Order view the hierarchy is on screen and this
  # is unnecessary; in a grouped view an entry sits next to entries from anywhere, and
  # without it there is nothing to say why it is here.
  def entry_source_badge(entry, viewing:)
    return if viewing.nil? || entry.list_id == viewing.id

    tag.span(class: 'entry-source') do
      concat tag.i(class: 'fa-solid fa-folder me-1')
      concat entry.list.name
    end
  end

  def entry_card(entry, **locals)
    render("entries/entry_#{entry.media.downcase}", entry: entry, **locals)
      .to_str
      .gsub(BETWEEN_TAGS, "><")
      .html_safe # rubocop:disable Rails/OutputSafety -- re-wrapping our own rendered output
  end
end
