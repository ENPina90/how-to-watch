# frozen_string_literal: true

# YouTube shipped with no autoplay parameter, so its embeds never started on their own
# however the channel was set. SourceCatalog now declares one, but the catalog only ever
# creates rows, so the row already in each database needs it set here.
#
# MEGA needs no row change: its flag goes in the key fragment, which Source handles by slug.
# Google Drive's preview player cannot autoplay at all, so there is nothing to set for it.
class AddAutoplayParamToYoutubeSource < ActiveRecord::Migration[8.1]
  SLUG = 'youtube'
  PARAM = 'autoplay'

  def up
    # Only fills a blank, so a parameter an admin has since set through the UI is left alone.
    Source.where(slug: SLUG, autoplay_param: [nil, '']).update_all(autoplay_param: PARAM, updated_at: Time.current)
  end

  def down
    Source.where(slug: SLUG, autoplay_param: PARAM).update_all(autoplay_param: nil, updated_at: Time.current)
  end
end
