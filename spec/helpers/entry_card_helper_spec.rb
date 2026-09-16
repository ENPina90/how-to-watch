require 'rails_helper'

# The two lines a fanedit card carries in place of a year and a rating. Both build a link
# out of user-typed text, so what they do when the ids are missing -- and what they do with
# the text itself -- is worth pinning down: an entry with nothing to link by should read as
# plain words rather than as a link to nowhere.
RSpec.describe EntryCardHelper, type: :helper do
  def entry(**attrs) = build_stubbed(:entry, media: 'fanedit', **attrs)

  it 'links the original through imdb' do
    html = helper.fanedit_origin(entry(fanedit_type: 'FanFix', original: 'Star Wars', imdb: 'tt0076759'))
    expect(html).to include('FanFix edit of')
    expect(html).to include('https://www.imdb.com/title/tt0076759/')
    expect(html).to include('>Star Wars</a>')
  end

  it 'falls back to the letterboxd slug' do
    html = helper.fanedit_origin(entry(fanedit_type: 'FanMix', original: 'Dune', imdb: nil, letterboxd_slug: 'dune-2021'))
    expect(html).to include('https://letterboxd.com/film/dune-2021/')
  end

  it 'leaves the original as text with no ids' do
    html = helper.fanedit_origin(entry(fanedit_type: 'FanFix', original: 'Some Cut', imdb: nil, letterboxd_slug: nil))
    expect(html).to eq('FanFix edit of Some Cut')
  end

  it 'says nothing when there is nothing to say' do
    expect(helper.fanedit_origin(entry(fanedit_type: nil, original: nil))).to be_nil
    expect(helper.fanedit_credit(entry(faneditor: nil))).to be_nil
  end

  it 'drops the type when there is none' do
    expect(helper.fanedit_origin(entry(fanedit_type: nil, original: 'X', imdb: nil, letterboxd_slug: nil))).to eq('Edit of X')
  end

  it 'links the faneditor to the fanedit link' do
    html = helper.fanedit_credit(entry(faneditor: 'Harmy', fanedit_link: 'https://fanedit.test/d'))
    expect(html).to include('By <a')
    expect(html).to include('https://fanedit.test/d')
  end

  it 'names the faneditor without a link' do
    expect(helper.fanedit_credit(entry(faneditor: 'Harmy', fanedit_link: nil))).to eq('By Harmy')
  end

  it 'escapes what it interpolates' do
    html = helper.fanedit_origin(entry(fanedit_type: 'FanFix', original: '<script>x</script>', imdb: nil, letterboxd_slug: nil))
    expect(html).not_to include('<script>')
  end
end
