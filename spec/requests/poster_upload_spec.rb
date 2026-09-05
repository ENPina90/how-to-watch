# frozen_string_literal: true

require 'rails_helper'

# The way out of the poster picker when none of the candidates is any good. It shares an
# endpoint with picking one of them: a URL for the server to go and fetch, or a file the
# browser sends directly.
RSpec.describe 'Uploading a poster' do
  let(:owner) { create(:user) }
  let(:list) { create(:list, user: owner) }
  let(:entry) { create(:entry, list: list, name: 'Fantasmas') }

  # A one-pixel PNG, so the sniffed type is a real one rather than whatever the test says.
  def png_bytes
    [137, 80, 78, 71, 13, 10, 26, 10].pack('C*') +
      ['0000000d49484452000000010000000108060000001f15c4890000000a49444154789c6360000002000100' \
       '05fe02fea7b7d3ec0000000049454e44ae426082'].pack('H*')
  end

  def upload(bytes, filename:, type: 'image/png', as: owner)
    file = Tempfile.new(['poster', File.extname(filename)], binmode: true)
    file.write(bytes)
    file.rewind
    sign_in as
    patch update_poster_entry_path(entry),
          params: { poster: Rack::Test::UploadedFile.new(file.path, type, original_filename: filename) }
  end

  it 'attaches the image the user picked' do
    upload(png_bytes, filename: 'my-poster.png')

    expect(response).to be_successful
    expect(entry.reload.poster).to be_attached
    expect(entry.poster.blob.content_type).to eq('image/png')
  end

  it 'names the file after the entry, the way the URL path does' do
    upload(png_bytes, filename: 'DSC_0042.png')

    expect(entry.reload.poster.filename.to_s).to start_with("poster_#{entry.id}_")
    expect(entry.poster.filename.to_s).to end_with('.png')
  end

  # The type a browser sends is whatever the client chose to say, and this file is served
  # back to everyone who can see the entry.
  it 'refuses a file that is not really an image, whatever it claims to be' do
    upload('<svg onload="alert(1)"/>', filename: 'poster.png', type: 'image/png')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to match(/not a JPEG/)
    expect(entry.reload.poster).not_to be_attached
  end

  it 'refuses an image bigger than the cap' do
    stub_const('EntriesController::MAX_POSTER_BYTES', 10)

    upload(png_bytes, filename: 'huge.png')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to match(/over/)
    expect(entry.reload.poster).not_to be_attached
  end

  it 'says so when it was sent neither a file nor a URL' do
    sign_in owner

    patch update_poster_entry_path(entry)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(entry.reload.poster).not_to be_attached
  end

  # Same gate as every other write on an entry: update_poster is in check_edit_permissions.
  it 'does not let somebody else replace the poster' do
    upload(png_bytes, filename: 'my-poster.png', as: create(:user))

    expect(response).not_to be_successful
    expect(entry.reload.poster).not_to be_attached
  end
end
