# frozen_string_literal: true

require 'rails_helper'

# The poster picker lets somebody paste a link, which means the server can be pointed at an
# address of the user's choosing. These are the things it must refuse to go and fetch.
RSpec.describe RemoteImage do
  # A one-pixel PNG, so the sniffed type is a real one rather than whatever a header claims.
  def png_bytes
    [137, 80, 78, 71, 13, 10, 26, 10].pack('C*') +
      ['0000000d49484452000000010000000108060000001f15c4890000000a49444154789c6360000002000100' \
       '05fe02fea7b7d3ec0000000049454e44ae426082'].pack('H*')
  end

  def fetch(url, max_bytes: 10.megabytes)
    described_class.fetch(url, max_bytes: max_bytes,
                               accept: %w[image/jpeg image/png image/webp image/gif])
  end

  # `URI.open`, which this replaced, falls through to `File.open` for a string that is not
  # a URL -- so this one would have read the file off the disk and attached it as a poster
  # for everybody who can see the entry to download.
  describe 'addresses it will not open at all' do
    it 'refuses a local path' do
      expect(fetch('/etc/passwd').error).to be_present
    end

    it 'refuses a file:// URL' do
      expect(fetch('file:///etc/passwd').error).to be_present
    end

    it 'refuses a scheme that is not http or https' do
      expect(fetch('ftp://example.com/poster.png').error).to be_present
    end

    it 'refuses nonsense' do
      expect(fetch('not a url at all').error).to be_present
    end
  end

  # Anything the server can reach that the person pasting the link cannot. The cloud
  # metadata service is the one that matters most: it hands out credentials.
  describe 'addresses it will not fetch from' do
    it 'refuses the cloud metadata service' do
      result = fetch('http://169.254.169.254/latest/meta-data/iam/security-credentials/')

      expect(result.error).to match(/not one this server will fetch from/)
      expect(WebMock).not_to have_requested(:get, %r{169\.254\.169\.254})
    end

    it 'refuses loopback' do
      expect(fetch('http://127.0.0.1/poster.png').error).to be_present
      expect(fetch('http://[::1]/poster.png').error).to be_present
    end

    it 'refuses a private network address' do
      expect(fetch('http://10.0.0.5/poster.png').error).to be_present
      expect(fetch('http://192.168.1.1/poster.png').error).to be_present
      expect(fetch('http://172.16.0.1/poster.png').error).to be_present
    end

    # ::ffff:127.0.0.1 is loopback wearing an IPv6 coat, and passes an IPv6-only check.
    it 'refuses an IPv4 address mapped into IPv6' do
      expect(fetch('http://[::ffff:127.0.0.1]/poster.png').error).to be_present
    end

    it 'refuses a hostname that resolves somewhere private' do
      allow(Resolv).to receive(:getaddresses).with('internal.test').and_return(['10.1.2.3'])

      expect(fetch('http://internal.test/poster.png').error).to be_present
    end

    # A name answering with one public address and one private one is a name aimed at the
    # private one.
    it 'refuses a hostname that resolves to a public and a private address' do
      allow(Resolv).to receive(:getaddresses).with('mixed.test').and_return(['93.184.216.34', '127.0.0.1'])

      expect(fetch('http://mixed.test/poster.png').error).to be_present
    end

    # Following a redirect without re-checking is the same hole with one more step in it.
    it 'refuses a public address that redirects somewhere private' do
      allow(Resolv).to receive(:getaddresses).and_return(['93.184.216.34'])
      stub_request(:get, 'http://images.test/poster.png')
        .to_return(status: 302, headers: { 'Location' => 'http://169.254.169.254/latest/meta-data/' })

      expect(fetch('http://images.test/poster.png').error).to be_present
    end
  end

  describe 'what it accepts' do
    before { allow(Resolv).to receive(:getaddresses).and_return(['93.184.216.34']) }

    it 'returns the image and the type it sniffed' do
      stub_request(:get, 'http://images.test/poster.png').to_return(status: 200, body: png_bytes)

      result = fetch('http://images.test/poster.png')

      expect(result).to be_ok
      expect(result.content_type).to eq('image/png')
      expect(result.io.read).to eq(png_bytes)
    end

    # Active Storage serves the file back under the type recorded here, and the remote
    # server's word for it is not evidence. image/svg+xml is a way to hand a viewer a script.
    it 'refuses something that is not an image, whatever the response claims' do
      stub_request(:get, 'http://images.test/poster.png')
        .to_return(status: 200, body: '<svg onload="alert(1)"/>',
                   headers: { 'Content-Type' => 'image/png' })

      expect(fetch('http://images.test/poster.png').error).to match(/not a JPEG/)
    end

    it 'refuses an image over the cap' do
      stub_request(:get, 'http://images.test/poster.png').to_return(status: 200, body: png_bytes)

      expect(fetch('http://images.test/poster.png', max_bytes: 10).error).to match(/too large/)
    end

    it 'refuses an address that answers with an error' do
      stub_request(:get, 'http://images.test/poster.png').to_return(status: 404)

      expect(fetch('http://images.test/poster.png').error).to be_present
    end

    it 'follows a redirect that stays on the public internet' do
      stub_request(:get, 'http://images.test/poster.png')
        .to_return(status: 302, headers: { 'Location' => 'http://images.test/real.png' })
      stub_request(:get, 'http://images.test/real.png').to_return(status: 200, body: png_bytes)

      expect(fetch('http://images.test/poster.png')).to be_ok
    end

    it 'gives up on a redirect loop' do
      stub_request(:get, 'http://images.test/poster.png')
        .to_return(status: 302, headers: { 'Location' => 'http://images.test/poster.png' })

      expect(fetch('http://images.test/poster.png').error).to match(/redirects too many times/)
    end
  end
end
