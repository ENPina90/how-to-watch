# Production always has at least one active imdb provider seeded (rails sources:seed).
# Specs that render the player need the same, otherwise embed_url is blank and the watch
# action correctly redirects with "No video source available".
RSpec.shared_context 'with a playable provider' do
  let!(:playable_provider) do
    Source.create!(
      name: 'Spec provider', kind: 'imdb', active: true, position: 1, autoplay_param: 'autoplay',
      templates: {
        'movie' => 'https://spec.test/movie/%{imdb}',
        'series' => 'https://spec.test/tv/%{series_imdb}/%{season}/%{episode}',
        'episode' => 'https://spec.test/tv/%{series_imdb}/%{season}/%{episode}',
        'anime' => 'https://spec.test/tv/%{series_imdb}/%{season}/%{episode}'
      }
    )
  end
end

RSpec.configure do |config|
  config.include_context 'with a playable provider', :needs_provider
end
