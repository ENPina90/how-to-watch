# frozen_string_literal: true

# Small formatting for the reel admin page. Runtimes and offsets are read here as "how far
# into three quarters of an hour of adverts", which minutes answer and seconds do not.
module CommercialReelsHelper
  def reel_length(reel)
    return 'unknown' unless reel.duration_seconds.to_i.positive?

    clock(reel.duration_seconds)
  end

  # The years a reel answers for, as it reads in a listing: one year where it covers one.
  def reel_years(reel)
    reel.starts_year == reel.ends_year ? reel.starts_year.to_s : "#{reel.starts_year}–#{reel.ends_year}"
  end

  def clock(seconds)
    seconds = seconds.to_i
    format('%<minutes>d:%<seconds>02d', minutes: seconds / 60, seconds: seconds % 60)
  end
end
