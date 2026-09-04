# frozen_string_literal: true

# When a provider's domain should be checked again.
#
# Streaming domains here are rented, not owned: ours is a registration that has to be
# renewed, and vidsrc's rotate on their own schedule -- the domains they told everyone to
# adopt in October 2025 were on their at-risk list by August 2026. Either way the failure
# is the same and it is silent: the embed simply stops loading, and nobody finds out until
# somebody tries to watch something.
#
# A date per provider turns that into something the app can warn about in advance.
class AddValidUntilToSources < ActiveRecord::Migration[8.0]
  # Only providers whose address can lapse get a date. Drive, MEGA, YouTube and the Archive
  # are not going anywhere, and a date on them would be noise that trains people to ignore
  # the warnings that matter.
  #
  # Windows reflect how much confidence each one has earned:
  #   * framerelay.dev -- registered 2026-09-04 for a year, so the date is the real one;
  #   * vidsrc2 / vidsrc-ir -- the provider's current recommendation, but their
  #     recommendations have a shelf life of well under a year in practice;
  #   * vidsrc-embed.ru / vidsrcme -- already named on the provider's at-risk list and
  #     working only by inertia, so they are checked again soon.
  WINDOWS = {
    'framerelay'      => 365,
    'vidsrc2'         => 180,
    'vidsrc-ir'       => 180,
    'vidsrc-embed.ru' => 60,
    'vidsrcme'        => 60
  }.freeze

  def up
    add_column :sources, :valid_until, :date

    # Partial: the column is null for everything that cannot lapse, and those rows are the
    # majority, so the index only carries the handful of providers a scan actually reads.
    add_index :sources, :valid_until, where: 'valid_until IS NOT NULL'

    WINDOWS.each do |slug, days|
      Source.where(slug: slug).update_all(valid_until: Date.current + days, updated_at: Time.current)
    end
  end

  def down
    remove_index :sources, :valid_until
    remove_column :sources, :valid_until
  end
end
