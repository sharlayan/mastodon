# frozen_string_literal: true

require 'rails_helper'

RSpec.describe REST::MediaAttachmentSerializer do
  let(:account) { Fabricate(:account) }
  let(:status) { Fabricate(:status, account: account, visibility: :public) }
  let(:drive_file) { DriveFile.create!(account: account, file: attachment_fixture('attachment.jpg')) }
  let!(:attachment) do
    drive_file.build_pointer(account).tap do |pointer|
      pointer.status = status
      pointer.save!
    end
  end

  let(:original_path) { "/drive_media/#{attachment.drive_access_key}/original" }
  let(:preview_path) { "/drive_media/#{attachment.drive_access_key}/small" }

  it 'uses drive resolver URLs in REST output' do
    result = serialized_record_json(attachment, described_class)

    expect(URI(result['url']).path).to eq(original_path)
    expect(URI(result['preview_url']).path).to eq(preview_path)
  end

  it 'uses drive resolver URLs in ActivityPub output' do
    result = serialized_record_json(status, ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter)
    document = result.fetch('attachment').first

    expect(URI(document['url']).path).to eq(original_path)
    expect(URI(document.dig('icon', 'url')).path).to eq(preview_path)
  end

  it 'uses drive resolver URLs in SEO output' do
    result = serialized_record_json(status, SEO::SocialMediaPostingSerializer, adapter: SEO::Adapter)
    image = result.fetch('image').first

    expect(URI(image['contentURL']).path).to eq(original_path)
    expect(URI(image['thumbnailURL']).path).to eq(preview_path)
  end

  it 'uses the original DriveFile URLs in Misskey-compatible output' do
    result = MisskeyCompat::DriveFileSerializer.serialize(attachment)

    expect(URI(result[:url]).path).to eq(drive_file.file.url(:original))
    expect(URI(result[:thumbnailUrl]).path).to eq(drive_file.file.url(:small))
  end

  it 'uses the redownload proxy for an evicted remote attachment in Misskey-compatible output' do
    remote_attachment = MediaAttachment.create!(
      account: account,
      status: status,
      remote_url: 'https://remote.example/media.jpg'
    )

    result = MisskeyCompat::DriveFileSerializer.serialize(remote_attachment)

    expect(remote_attachment).to be_needs_redownload
    expect(URI(result[:url]).path).to eq("/media_proxy/#{remote_attachment.id}/original")
    expect(URI(result[:thumbnailUrl]).path).to eq("/media_proxy/#{remote_attachment.id}/small")
  end
end
