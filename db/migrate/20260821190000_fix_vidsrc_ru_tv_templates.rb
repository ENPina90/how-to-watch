# frozen_string_literal: true

# Two fixes to the vidsrc.ru provider's tv templates:
#
#   * `series` omitted season/episode, so every series entry resolved to a
#     season-less embed URL and the player fell back to S1E1.
#   * `anime` was missing entirely, so anime entries resolving to this provider
#     got nil from Source#url_for and silently fell back to the legacy (dead)
#     source column. vidsrc.ru has no anime endpoint -- anime uses the tv one.
#
# db/seeds/sources.rb is create-only, so already-seeded rows need this fix.
class FixVidsrcRuTvTemplates < ActiveRecord::Migration[8.0]
  SLUG = "vidsrc-embed.ru"
  BROKEN_SERIES = "https://vidsrc-embed.ru/embed/tv?imdb=%{series_imdb}&ds_lang=en"
  TV = "https://vidsrc-embed.ru/embed/tv?imdb=%{series_imdb}&season=%{season}&episode=%{episode}&ds_lang=en"

  def up
    update_templates do |templates|
      # Only rewrite the exact value we shipped, so a template an admin has since
      # edited through the UI is left alone.
      templates["series"] = TV if templates["series"] == BROKEN_SERIES
      templates["anime"] = TV if templates["anime"].blank?
    end
  end

  def down
    update_templates do |templates|
      templates["series"] = BROKEN_SERIES if templates["series"] == TV
      templates.delete("anime") if templates["anime"] == TV
    end
  end

  private

  def update_templates
    source = Source.find_by(slug: SLUG)
    return if source.nil?

    templates = source.templates.dup
    yield templates
    source.update!(templates: templates) if templates != source.templates
  end
end
