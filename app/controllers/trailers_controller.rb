# frozen_string_literal: true

# /trailers -- trailers for films across the catalogue, one after another, each with a way to
# the film it belongs to. Channel 0 on /cable is the same reel with the dial around it.
#
# Nothing here reads or writes the per-user tables. Watching a trailer is not watching the
# film, and the only thing kept is the session's note of which trailers were just shown.
class TrailersController < ApplicationController
  include NoPlaybackOnMobile
  include TrailerPicking

  def show
    @trailer = next_trailer

    # The cable page's frame: the picture, and nothing around it but the card.
    @cable = true
    @sidebar_collapsed = true
    @hide_sidebar = true

    render layout: 'special_layout'
  end
end
