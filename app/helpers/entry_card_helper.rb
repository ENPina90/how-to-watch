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
  def entry_card(entry, **locals)
    render("entries/entry_#{entry.media.downcase}", entry: entry, **locals)
      .to_str
      .gsub(BETWEEN_TAGS, "><")
      .html_safe # rubocop:disable Rails/OutputSafety -- re-wrapping our own rendered output
  end
end
