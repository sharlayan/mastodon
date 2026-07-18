# frozen_string_literal: true

require 'rails_helper'
require 'mastodon/cli/emoji'

RSpec.describe Sharlayan::CLI::EmojiArchive do
  let(:cli) { Mastodon::CLI::Emoji.new }
  let(:tmp_path) { Rails.root.join('tmp', 'cli-archive-spec') }

  before { FileUtils.mkdir_p(tmp_path) }
  after { FileUtils.rm_rf(tmp_path) }

  it 'imports Misskey ZIP metadata' do
    archive_path = tmp_path.join('emoji.zip')
    manifest = {
      emojis: [
        {
          fileName: 'blobcat.jpg',
          emoji: { name: 'blobcat', category: 'Cats', license: 'CC0', aliases: %w(cat blob) },
        },
      ],
    }

    Zip::OutputStream.open(archive_path) do |zip|
      zip.put_next_entry('blobcat.jpg')
      zip.write(attachment_fixture('attachment.jpg').read)
      zip.put_next_entry('meta.json')
      zip.write(JSON.generate(manifest))
    end

    expect { cli.invoke(:import, [archive_path]) }.to change(CustomEmoji, :count).by(1)

    emoji = CustomEmoji.last
    expect(emoji).to have_attributes(shortcode: 'blobcat', license: 'CC0', aliases: contain_exactly('cat', 'blob'))
    expect(emoji.category.name).to eq('Cats')
  end

  it 'exports Mastodon metadata with the image' do
    category = Fabricate(:custom_emoji_category, name: 'Cats')
    emoji = Fabricate(:custom_emoji, category:, aliases: %w(cat blob), license: 'CC0')

    cli.invoke(:export, [tmp_path])

    manifest = nil
    Gem::Package::TarReader.new(Zlib::GzipReader.open(tmp_path.join('export.tar.gz'))) do |tar|
      entry = tar.find { |candidate| candidate.full_name == 'metadata.json' }
      manifest = JSON.parse(entry.read)
    end

    metadata = manifest.dig('emojis', "#{emoji.shortcode}#{File.extname(emoji.image_file_name)}")
    expect(metadata).to include('category' => 'Cats', 'license' => 'CC0', 'aliases' => contain_exactly('cat', 'blob'))
  end
end
