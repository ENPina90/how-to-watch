# frozen_string_literal: true

# A decade on the cable dial: a channel with no list behind it, whose schedule is dealt from
# every public entry made in those years.
#
# Not a List, and on purpose. A channel on the dial has to be `default`, and a default list
# subscribes every account and sits in every sidebar -- the opposite of a channel that only
# means anything on /cable. A list would also need entries of its own, which means copies of
# films that already live somewhere. An era is a question about the catalogue ("what is from
# the 80s") and a row of listings, so that is all it is: the schedule's rows name it by
# `era`, and the entries they play stay in the channels they were filed in -- which is where
# the guide links back to.
#
# Always at the end of the dial, in this order, and not the admin's to move or remove.
class CableEra
  attr_reader :key, :name, :years

  def initialize(key:, name:, years:)
    @key = key
    @name = name
    @years = years
    freeze
  end

  # Newest first, the way the dial reads down. The keys are what the addresses carry, and are
  # spelled as years rather than as the names so that none of them can be read as a number:
  # "80s" cast to an id is 80, and list 80 would be served in its place.
  ALL = [
    new(key: "2020s", name: "20s", years: 2020..2029),
    new(key: "2010s", name: "10s", years: 2010..2019),
    new(key: "2000s", name: "00s", years: 2000..2009),
    new(key: "1990s", name: "90s", years: 1990..1999),
    new(key: "1980s", name: "80s", years: 1980..1989),
    new(key: "1970s", name: "70s", years: 1970..1979),
    new(key: "1960s", name: "60s", years: 1960..1969),
    new(key: "golden-age", name: "Golden Age", years: 1900..1959)
  ].freeze

  def self.all = ALL

  # By the key in its address, and nothing else -- nil for a list id, which is how the cable
  # page tells the two apart.
  def self.find(key) = ALL.find { |era| era.key == key.to_s }

  # How a page names the channel it is on: the guide's rows, the chrome, the dial. A string,
  # so it can never be mistaken for a list's id when the two are compared.
  def id = key

  def to_param = key

  # Every public entry from these years, one per film, preloaded with what laying out a day
  # asks of each.
  #
  # Public only: the dial plays to anybody who opens /cable, and a private channel is not its
  # owner's to broadcast by accident. One copy per film, by catalogue_key, so a film filed in
  # four channels is not four times as likely to come up. The lowest id wins, which is the
  # copy filed first -- the one that plays, and the channel the guide sends you back to.
  def entries
    Entry.joins(:list)
         .where(lists: { private: [false, nil] }, year: years)
         .includes(:provider, :subentries, list: :provider)
         .order(:id)
         .to_a
         .uniq(&:catalogue_key)
  end
end
