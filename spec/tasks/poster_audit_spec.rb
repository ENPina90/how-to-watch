require 'rails_helper'
require 'rake'

# Most posters are Active Storage attachments now, and the ones that go missing go missing
# in Cloudinary rather than in the database -- every column still looks filled in. So the
# audit asks the same URL the channel row asks for, and asks it over the wire.
RSpec.describe 'posters:audit' do
  let(:list) { create(:list, name: 'Funny') }

  before(:all) do
    Rake::Task.define_task(:environment)
    Rake.application.rake_require('tasks/poster_audit') unless Rake::Task.task_defined?('posters:audit')
  end

  before { Rake::Task['posters:audit'].reenable }

  def run
    output = nil
    expect { output = capture_stdout { Rake::Task['posters:audit'].invoke } }.not_to raise_error
    output
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def serving(url, status: 200, content_type: 'image/jpeg')
    stub_request(:head, url).to_return(status: status, headers: { 'Content-Type' => content_type })
  end

  def attach_poster(entry)
    entry.poster.attach(io: StringIO.new('x'), filename: 'poster.jpg', content_type: 'image/jpeg')
    # Cloudinary is the only service in development and production. The blob is written to
    # the test service first, then relabelled, so the audit follows the branch that the
    # channel rows actually render from.
    entry.poster.blob.update_column(:service_name, 'cloudinary')
    entry
  end

  it 'reports an entry whose pic URL is gone' do
    entry = create(:entry, list: list, name: 'Fantasmas', pic: 'https://img.test/gone.jpg')
    serving('https://img.test/gone.jpg', status: 404)

    expect(run).to include('Fantasmas', 'HTTP 404', "/entries/#{entry.id}/edit")
  end

  it 'leaves an entry alone when its broken pic is covered by an attached poster' do
    entry = attach_poster(create(:entry, list: list, name: 'Ted Lasso', pic: 'https://img.test/gone.jpg'))
    serving(%r{res\.cloudinary\.com/.*#{entry.poster.key}})

    expect(run).to include('Every poster loads.')
  end

  it 'reports an attached poster whose Cloudinary asset is missing' do
    entry = attach_poster(create(:entry, list: list, name: 'The Franchise'))
    serving(%r{res\.cloudinary\.com/.*#{entry.poster.key}}, status: 404)

    output = run
    expect(output).to include('The Franchise', 'HTTP 404')
    expect(output).to include('Broken:          1')
  end

  it 'reports a URL that answers with something other than an image' do
    create(:entry, list: list, name: 'Landman', pic: 'https://img.test/oops.html')
    serving('https://img.test/oops.html', content_type: 'text/html')

    expect(run).to include('Landman', 'not an image')
  end

  it 'accepts a pic held inline as a data URI' do
    create(:entry, list: list, name: "SNL '70s", pic: 'data:image/jpeg;base64,/9j/4AAQSkZJRg==')

    expect(run).to include('Every poster loads.')
  end

  it 'reports an entry carrying no image at all' do
    create(:entry, list: list, name: 'Bonanza', pic: nil)

    expect(run).to include('Bonanza', 'no image on the entry')
  end
end
