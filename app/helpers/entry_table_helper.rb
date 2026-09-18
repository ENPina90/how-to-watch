# frozen_string_literal: true

# The pieces of the admin tables -- /admin/entries and /admin/subentries -- that are drawn once
# per row or once per heading. Kept as small as they can be, because "once per row" is
# thousands of times on one page.
module EntryTableHelper
  # A column heading that sorts by itself. Pressing the column already sorted turns it round;
  # pressing any other starts it ascending. The arrow marks the current sort, and aria-sort
  # says the same thing to a screen reader. Points at whichever table is being drawn -- the
  # address is this page's own with the sort changed.
  def entry_table_heading(label, key, sort:, direction:)
    active = key == sort
    next_direction = active && direction == 'asc' ? 'desc' : 'asc'
    arrow = if active
              tag.i(class: "fa-solid fa-caret-#{direction == 'asc' ? 'up' : 'down'}", aria: { hidden: true })
            end

    tag.th(scope: 'col', aria: { sort: active ? "#{direction}ending" : 'none' }) do
      link_to(url_for(sort: key, direction: next_direction)) { safe_join([label, arrow].compact, ' ') }
    end
  end

  # "S01E04", the way episode lists write it -- or as much of it as the row knows. Imports
  # leave either half empty often enough that a label assuming both would read "S01E" or
  # "SE04".
  def subentry_table_label(subentry)
    season = subentry.season && format('S%02d', subentry.season)
    episode = subentry.episode && format('E%02d', subentry.episode)
    [season, episode].compact.join
  end

  # What an episode is called in the table, in a flash and in a delete prompt. Some imports
  # arrive without a name, and a blank would leave the row with nothing to click and the
  # prompt asking to delete "".
  def subentry_table_name(subentry)
    subentry.name.presence || [subentry.entry&.name, subentry_table_label(subentry)].compact_blank.join(' ').presence || 'Untitled episode'
  end

  # `stream` is three-valued and the table says so: a tick for known to work, a cross for
  # known broken -- which is what keeps an entry off the cable schedule -- and a dash for
  # never checked, which is not the same as either.
  #
  # The mark is also the switch: pressing it flips working and broken, and a dash becomes
  # working (entry-table sends it). Made operable with attributes on the mark itself rather
  # than by wrapping it in a <button>: a wrapper would be another element on every one of
  # several thousand rows, and the click is delegated from the table anyway.
  def entry_stream_mark(stream)
    flip = { role: 'button', tabindex: 0 }
    case stream
    when true  then tag.i(**flip, class: 'fa-solid fa-check et-ok et-flip', title: 'Working (press to mark broken)')
    when false then tag.i(**flip, class: 'fa-solid fa-xmark et-bad et-flip', title: 'Broken (press to mark working)')
    else tag.span('–', **flip, class: 'et-na et-flip', title: 'Never checked (press to mark working)')
    end
  end
end
