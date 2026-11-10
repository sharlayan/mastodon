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

  it 'uses drive resolver URLs in REST, ActivityPub, SEO and Misskey-compatible output' do
    rest = serialized_record_json(attachment, described_class)
    document = serialized_record_json(status, ActivityPub::NoteSerializer, adapter: ActivityPub::Adapter).fetch('attachment').first
    image = serialized_record_json(status, SEO::SocialMediaPostingSerializer, adapter: SEO::Adapter).fetch('image').first
    misskey = MisskeyCompat::DriveFileSerializer.serialize(attachment)

    expect(URI(rest['url']).path).to eq(original_path)
    expect(URI(rest['preview_url']).path).to eq(preview_path)
    expect(URI(document['url']).path).to eq(original_path)
    expect(URI(document.dig('icon', 'url')).path).to eq(preview_path)
    expect(URI(image['contentURL']).path).to eq(original_path)
    expect(URI(image['thumbnailURL']).path).to eq(preview_path)
    expect(URI(misskey[:url]).path).to eq(original_path)
    expect(URI(misskey[:thumbnailUrl]).path).to eq(preview_path)
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

  describe 'a chat attachment' do
    let(:viewer) { Fabricate(:user).account }
    let(:media) { Fabricate(:media_attachment, account: account, status: nil) }

    before do
      room = ChatConversation.create!(conversation_type: :group, title: 'Room', owner_account: account)
      room.memberships.create!(account: account, role: :owner)
      room.memberships.create!(account: viewer)
      room.messages.create!(account: account, text: 'sent').media_attachments << media
    end

    def preview_url(record)
      described_class.new(record.reload, current_account: viewer).as_json[:preview_url]
    end

    it 'gives a protected preview of an image but no preview of audio without a thumbnail or an unknown file' do
      expect(URI(preview_url(media)).path).to eq("/media_proxy/#{media.id}/small")

      media.update_columns(type: MediaAttachment.types[:audio], file_content_type: 'audio/mpeg')

      expect(preview_url(media)).to be_nil

      media.update_columns(type: MediaAttachment.types[:unknown], file_content_type: 'application/octet-stream')

      expect(preview_url(media)).to be_nil
    end
  end
end
