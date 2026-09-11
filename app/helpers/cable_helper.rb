# frozen_string_literal: true

module CableHelper
  # Times on a cable channel are read off a clock, so they are shown in the zone the
  # schedule was laid out in rather than the server's. Every viewer sees the listing the
  # channel was actually built against.
  def cable_time(time, zone = CableSchedule.zone)
    time.in_time_zone(zone).strftime("%-l:%M %p").downcase
  end

  # The column where one day's listings give way to the next. The track runs for days now,
  # so a column reading 12:00 AM says nothing on its own -- there are four of them.
  def cable_day(time, zone = CableSchedule.zone)
    time.in_time_zone(zone).strftime("%a %-e %b").upcase
  end

  # The clock in the guide's corner cell, seconds and all -- the old guides ran one, and it
  # is the only thing on the grid that says what time it actually is.
  def cable_clock(time, zone = CableSchedule.zone)
    time.in_time_zone(zone).strftime("%-l:%M:%S")
  end

  # What a listing is about, split into the show it belongs to and the episode of it.
  #
  # The split is the whole point. A grid cell gets `show` and nothing else -- an afternoon
  # of one series is thirteen cells reading "Babylon 5", which is a channel; the same
  # thirteen reading "Babylon 5 — S2E14 There All the Honor Lies" is a wall of text with
  # the only word that varies pushed off the right-hand edge. Everything else is said once,
  # in the panel, about the one programme somebody has actually pointed at.
  Programme = Struct.new(:show, :number, :episode_title, keyword_init: true) do
    # What to call this at the top of the banner: the episode where there is one, since the
    # show it belongs to is said underneath rather than folded into the title.
    def headline
      episode_title.presence || show
    end
  end

  # A title carrying what should have been in columns. Imports leave two shapes behind: a
  # series added a season at a time, "The Simpsons - Season 1", and an episode whose season
  # and episode columns were never filled in, "MARVEL S01E15 The Unworthy Thor". Both name
  # the show first and the rest after, so both come apart the same way -- and there is
  # nowhere else to read them from, since the columns behind them are blank.
  SEASON_IN_TITLE = /\A(?<show>.+?)[\s:.\-–—]+season\s*(?<season>\d+)\z/i
  EPISODE_IN_TITLE = /
    \A(?<show>.+?)[\s:.\-–—]+
    s(?<season>\d+)[\s.\-–—]*e(?<episode>\d+)
    [\s:.\-–—]*(?<title>.*)\z
  /xi

  # Four shapes arrive here and all four have to leave looking the same:
  #
  #   a series or anime playing one of its episodes -- the show is the entry, the episode
  #   is the subentry, and both are already in columns;
  #   a standalone `episode` -- the show is in `series` and the entry itself is the episode;
  #   a series named a season at a time, where the season is only in the title;
  #   and anything with its number written into its title, which is what an import leaves
  #   when nobody filled the columns in.
  #
  # Columns win wherever there are any; the title is read only for what they do not say.
  def cable_programme(slot)
    entry = slot.entry
    named = cable_season_in_title(entry)

    if (subentry = slot.subentry)
      Programme.new(show: named.show,
                    number: cable_subentry_number(entry, subentry),
                    episode_title: subentry.name.presence)
    elsif entry.media == "episode"
      parsed = cable_episode_in_title(entry.name)
      Programme.new(show: entry.series.presence || parsed&.show || entry.name,
                    number: cable_episode_number(entry.season, entry.episode) || parsed&.number,
                    episode_title: parsed&.episode_title || entry.name)
    else
      cable_episode_in_title(entry.name) || named
    end
  end

  # The banner's headline, and the line under it: what show this is, which episode, and when
  # it is from. The show is left out when the headline is already saying it -- a film would
  # otherwise have its own name twice, once in each size.
  def cable_programme_headline(slot)
    cable_programme(slot).headline
  end

  def cable_programme_context(slot)
    programme = cable_programme(slot)
    show = programme.show unless programme.show == programme.headline

    [show, programme.number, slot.entry.year].compact_blank.join(" · ")
  end

  # How long the programme runs, as the catalogue has it rather than as the slot was laid
  # out -- a slot runs on to the next five-minute mark and the difference is the break, so
  # its width is not the running time and should not be reported as one.
  def cable_runtime(slot)
    minutes = (slot.subentry&.length.presence || slot.entry.length).to_i
    return nil unless minutes.positive?
    return "#{minutes} min" if minutes < 60

    hours, rest = minutes.divmod(60)
    rest.zero? ? "#{hours} hr" : "#{hours} hr #{rest} min"
  end

  # The score out of ten. An episode's own where anyone recorded one, since the show's
  # average says nothing about which episode is on; zero is what an import writes when it
  # found nothing, and is not a rating of nought.
  def cable_rating(slot)
    score = [slot.subentry&.rating, slot.entry.rating].compact.map(&:to_f).find(&:positive?)
    return nil unless score

    format("%.1f/10", score)
  end

  # The genres, in the dot-separated run the rest of the panel is set in.
  def cable_genres(slot)
    slot.entry.genre.to_s.split(",").map(&:strip).compact_blank.join(" · ").presence
  end

  private

  # Anime number their episodes straight through rather than restarting each season, and
  # that is the number the show itself uses, so it is the one the listing should print --
  # where there is one. A show whose seasons were never squared up has no absolute number
  # to work out, and then the season and episode it does have are better than nothing.
  def cable_subentry_number(entry, subentry)
    if entry.media == "anime" && (absolute = subentry.calculate_absolute_episode_number).present?
      return "E#{absolute}"
    end

    cable_episode_number(subentry.season, subentry.episode)
  end

  # Nothing at all, or zero for both, means whoever imported this had no numbering to write
  # down -- it is not season nought episode nought. Half a number is still worth printing:
  # knowing it is episode three says where in the run the viewer has landed.
  def cable_episode_number(season, episode)
    season = season.presence&.to_i
    episode = episode.presence&.to_i
    return nil if season.to_i.zero? && episode.to_i.zero?

    [season && "S#{season}", episode && "E#{episode}"].compact.join
  end

  def cable_episode_in_title(name)
    match = EPISODE_IN_TITLE.match(name.to_s)
    return nil unless match

    Programme.new(show: match[:show].strip,
                  number: "S#{match[:season].to_i}E#{match[:episode].to_i}",
                  episode_title: match[:title].strip.presence)
  end

  # Only for a series or an anime. A film called "Silly Season 2" is a film called "Silly
  # Season 2", and there is no season of anything to take off it.
  def cable_season_in_title(entry)
    match = Entry::SERIES_MEDIA.include?(entry.media) && SEASON_IN_TITLE.match(entry.name.to_s)
    return Programme.new(show: entry.name) unless match

    Programme.new(show: match[:show].strip, number: "Season #{match[:season].to_i}")
  end
end
