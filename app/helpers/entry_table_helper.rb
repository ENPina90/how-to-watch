# frozen_string_literal: true

# The pieces of /admin/entries that are drawn once per row or once per heading. Kept as small
# as they can be, because "once per row" is several thousand times on one page.
module EntryTableHelper
  # A column heading that sorts by itself. Pressing the column already sorted turns it round;
  # pressing any other starts it ascending. The arrow marks the current sort, and aria-sort
  # says the same thing to a screen reader.
  def entry_table_heading(label, key, sort:, direction:)
    active = key == sort
    next_direction = active && direction == 'asc' ? 'desc' : 'asc'
    arrow = if active
              tag.i(class: "fa-solid fa-caret-#{direction == 'asc' ? 'up' : 'down'}", aria: { hidden: true })
            end

    tag.th(scope: 'col', aria: { sort: active ? "#{direction}ending" : 'none' }) do
      link_to(admin_entries_path(sort: key, direction: next_direction)) { safe_join([label, arrow].compact, ' ') }
    end
  end

  # `stream` is three-valued and the table says so: a tick for known to work, a cross for
  # known broken -- which is what keeps an entry off the cable schedule -- and a dash for
  # never checked, which is not the same as either.
  def entry_stream_mark(stream)
    case stream
    when true  then tag.i(class: 'fa-solid fa-check et-ok', title: 'Working')
    when false then tag.i(class: 'fa-solid fa-xmark et-bad', title: 'Broken')
    else tag.span('–', class: 'et-na', title: 'Never checked')
    end
  end
end
