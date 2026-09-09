# frozen_string_literal: true

# The commercial compilations this app ships with, and how they reach a database.
#
# The list is code for the same reason the provider list is: adding a reel is a reviewable
# diff that travels with the deploy, rather than something typed into a form on each
# environment in turn.
#
# Additive, also for the same reason. Existing rows are never modified -- a runtime filled
# in by hand, a video swapped for one that still embeds -- so `sync!` only creates reels
# this app knows about and the database does not.
#
# Coverage is by year where a year has its own compilation and by era where it does not.
# The ranges must not overlap; nothing enforces that, and two reels covering 1987 would
# simply mean 1987 films get one or the other.
#
# The runtimes are carried here rather than fetched, so a database seeded from scratch has
# them from the first boot. Without one a break can only begin somewhere in the first few
# minutes, because there is no telling how much reel there is left to spend -- which means
# every break on a channel opens with roughly the same adverts. Read from YouTube on
# 2026-09-09; `commercials:durations` refreshes them and fills in any reel added later.
class CommercialCatalog
  REELS = [
    { label: "1940s", starts_year: 1940, ends_year: 1949,
      youtube_id: "IFrkSiCvBo0", duration_seconds: 606 },
    { label: "1950s", starts_year: 1950, ends_year: 1959,
      youtube_id: "AR8Fc2abggg", duration_seconds: 599 },
    { label: "1960s", starts_year: 1960, ends_year: 1969,
      youtube_id: "US8Lf83ciUM", duration_seconds: 872 },
    { label: "1970s", starts_year: 1970, ends_year: 1979,
      youtube_id: "3dxysydEp54", duration_seconds: 534 },
    { label: "1980-85", starts_year: 1980, ends_year: 1985,
      youtube_id: "tgoUa2wWvAQ", duration_seconds: 3478 },
    { label: "1986", starts_year: 1986, ends_year: 1986,
      youtube_id: "fGUAx_EBcrg", duration_seconds: 2137 },
    { label: "1987", starts_year: 1987, ends_year: 1987,
      youtube_id: "NtT8WiKldPs", duration_seconds: 1827 },
    { label: "1988", starts_year: 1988, ends_year: 1988,
      youtube_id: "tooP12U1QVI", duration_seconds: 1481 },
    { label: "1989", starts_year: 1989, ends_year: 1989,
      youtube_id: "W-g6atUlpx4", duration_seconds: 1913 },
    { label: "1990", starts_year: 1990, ends_year: 1990,
      youtube_id: "0HnyI2Jd5ZM", duration_seconds: 1615 },
    { label: "1991", starts_year: 1991, ends_year: 1991,
      youtube_id: "dzKJ4QRoTok", duration_seconds: 1663 },
    { label: "1992", starts_year: 1992, ends_year: 1992,
      youtube_id: "SwW3rTdqEGI", duration_seconds: 1306 },
    { label: "1993", starts_year: 1993, ends_year: 1993,
      youtube_id: "RhPlE6sP3WM", duration_seconds: 2157 },
    { label: "1994", starts_year: 1994, ends_year: 1994,
      youtube_id: "1HBgJojaOGQ", duration_seconds: 1931 },
    { label: "1995", starts_year: 1995, ends_year: 1995,
      youtube_id: "ll8Bho3c_pw", duration_seconds: 1479 },
    { label: "1996", starts_year: 1996, ends_year: 1996,
      youtube_id: "UspnuAphzN8", duration_seconds: 2033 },
    { label: "1997", starts_year: 1997, ends_year: 1997,
      youtube_id: "8t5HROVIFkM", duration_seconds: 3672 },
    { label: "1998", starts_year: 1998, ends_year: 1998,
      youtube_id: "ib3csdQVpS8", duration_seconds: 3115 },
    { label: "1999", starts_year: 1999, ends_year: 1999,
      youtube_id: "b6A0HIRWtCU", duration_seconds: 2051 },
    { label: "2000", starts_year: 2000, ends_year: 2000,
      youtube_id: "VxutF3V6tmQ", duration_seconds: 1851 },
    { label: "2001", starts_year: 2001, ends_year: 2001,
      youtube_id: "L6IOVZlJ69U", duration_seconds: 2275 },
    { label: "2002", starts_year: 2002, ends_year: 2002,
      youtube_id: "aanXi683WW4", duration_seconds: 2045 },
    { label: "2003", starts_year: 2003, ends_year: 2003,
      youtube_id: "EwozEkHKMaY", duration_seconds: 1889 },
    { label: "2004", starts_year: 2004, ends_year: 2004,
      youtube_id: "Ig3_6dcQb08", duration_seconds: 3761 },
    { label: "2005", starts_year: 2005, ends_year: 2005,
      youtube_id: "Zy6FU2PSzLE", duration_seconds: 1093 },
    { label: "2006", starts_year: 2006, ends_year: 2006,
      youtube_id: "deZE2VBQVVM", duration_seconds: 2617 },
    { label: "2007", starts_year: 2007, ends_year: 2007,
      youtube_id: "JsNLs2L7dqE", duration_seconds: 1777 },
    { label: "2008", starts_year: 2008, ends_year: 2008,
      youtube_id: "xR41A8K6cQY", duration_seconds: 1980 },
    { label: "2009", starts_year: 2009, ends_year: 2009,
      youtube_id: "gQFcbCSRANE", duration_seconds: 1758 },
    { label: "2010-2019", starts_year: 2010, ends_year: 2019,
      youtube_id: "MSoemc-50jM", duration_seconds: 4914 },
    { label: "2020", starts_year: 2020, ends_year: 2020,
      youtube_id: "QCwqNWPaExQ", duration_seconds: 846 },
    { label: "2021", starts_year: 2021, ends_year: 2021,
      youtube_id: "YsWOyKaVVQc", duration_seconds: 652 },
    { label: "2022", starts_year: 2022, ends_year: 2022,
      youtube_id: "22EQao-QAng", duration_seconds: 1617 },
    { label: "2023", starts_year: 2023, ends_year: 2023,
      youtube_id: "DLRZrQx2hxs", duration_seconds: 1661 },
    { label: "2024", starts_year: 2024, ends_year: 2024,
      youtube_id: "hlYRx9TeXlM", duration_seconds: 2684 },
    { label: "2025", starts_year: 2025, ends_year: 2025,
      youtube_id: "5lFTclUWljM", duration_seconds: 5246 }
  ].freeze

  Result = Struct.new(:created, :kept, :failed, keyword_init: true) do
    def summary = "#{created.length} created, #{kept.length} kept, #{failed.length} failed"
  end

  def self.sync!
    result = Result.new(created: [], kept: [], failed: [])

    REELS.each do |attributes|
      if CommercialReel.exists?(youtube_id: attributes[:youtube_id])
        result.kept << attributes[:label]
        next
      end

      CommercialReel.create!(attributes)
      result.created << attributes[:label]
    rescue StandardError => e
      # One bad reel is a gap in one era's adverts, not a reason to leave the rest unseeded.
      Rails.logger.error("CommercialCatalog: #{attributes[:label]} failed: #{e.class}: #{e.message}")
      result.failed << attributes[:label]
    end

    result
  end
end
