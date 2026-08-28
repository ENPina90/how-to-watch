namespace :entries do
  desc "Fill a blank category on every series, season, anime and episode with its show's name"
  task backfill_categories: :environment do
    filled = 0
    unknown = 0

    # Only the blanks: a category set by hand is a decision, and this task is a backfill,
    # not a correction.
    scope = Entry.where(media: Entry::SHOW_MEDIA).where(category: [nil, ''])

    scope.find_each do |entry|
      show = entry.show_name

      if show.blank?
        unknown += 1
        next
      end

      # update_columns, not update: this writes one column on rows that are otherwise
      # untouched, and running validations here would fail on records that were already
      # invalid for unrelated reasons.
      entry.update_columns(category: show)
      filled += 1
    end

    puts "Categorised #{filled} #{'entry'.pluralize(filled)}."
    puts "Left #{unknown} alone with no show name to use." if unknown.positive?
  end
end
