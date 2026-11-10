# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompat::ChatSerializer do
  let(:owner) { Fabricate(:user).account }
  let(:member) { Fabricate(:user).account }
  let(:room) do
    ChatConversation.create!(conversation_type: :group, title: 'Room', description: 'Private group', owner_account: owner).tap do |conversation|
      conversation.memberships.create!(account: owner, role: :owner)
      conversation.memberships.create!(account: member, muted: true)
    end
  end

  def mid(record)
    MisskeyCompat::MiId.encode(record.id)
  end

  it 'serializes direct message recipients independently of the viewer and retains edit precision' do
    conversation = ChatConversation.create!(conversation_type: :direct, direct_key: [owner.id, member.id].sort.join(':'))
    conversation.memberships.create!(account: owner)
    conversation.memberships.create!(account: member)
    message = conversation.messages.create!(account: owner, text: 'Hello', edited_at: Time.utc(2026, 11, 3, 0, 0, 0, 123_000))

    [owner, member].each do |viewer|
      expect(described_class.message(message, viewer: viewer)).to include(
        id: mid(message), fromUserId: mid(owner), toUserId: mid(member), toRoomId: nil,
        text: 'Hello', editedAt: '2026-11-03T00:00:00.123Z', deletedAt: nil,
        fromUser: include(id: mid(owner)), toUser: include(id: mid(member))
      )
    end
  end

  it 'includes room state, membership and invitation IDs in the Misskey format' do
    invitee = Fabricate(:user).account
    invitation = room.invitations.create!(inviter_account: owner, invitee_account: invitee)
    room.update!(archived_at: Time.current)

    expect(described_class.room(room, viewer: member)).to include(id: mid(room), name: 'Room', ownerId: mid(owner), isMuted: true, isArchived: true, invitationExists: false)
    expect(described_class.invitation(invitation, viewer: invitee)).to include(id: mid(invitation), roomId: mid(room), userId: mid(invitee), room: include(invitationExists: true))
    membership = room.memberships.find_by!(account: member)
    expect(described_class.membership(membership, viewer: member)).to include(id: mid(membership), userId: mid(member), roomId: mid(room), user: include(id: mid(member)), room: include(id: mid(room)))
  end

  it 'uses the protected media proxy and preserves the Drive file ID' do
    drive_file = DriveFile.create!(account: owner, file: attachment_fixture('attachment.jpg'))
    media = drive_file.build_pointer(owner)
    media.save!
    message = room.messages.create!(account: owner, text: 'attachment')
    message.media_attachments << media

    payload = described_class.message(message, viewer: member)

    expect(payload).to include(fileId: mid(drive_file), file: include(id: mid(drive_file)))
    expect(payload.dig(:file, :url)).to include("/media_proxy/#{media.id}/original")
    expect(payload.dig(:file, :thumbnailUrl)).to include("/media_proxy/#{media.id}/small")
  end

  it 'gives no thumbnail of audio without one' do
    media = Fabricate(:media_attachment, account: owner, status: nil)
    media.update_columns(type: MediaAttachment.types[:audio], file_content_type: 'audio/mpeg')
    message = room.messages.create!(account: owner, text: 'attachment')
    message.media_attachments << media

    expect(described_class.message(ChatMessage.find(message.id), viewer: member).dig(:file, :thumbnailUrl)).to be_nil
  end

  describe 'the name of an attachment from another server' do
    let(:remote) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob') }
    let(:media) { MediaAttachment.create!(account: remote, remote_url: 'https://remote.test/files/abc', file_content_type: 'image/png') }
    let(:message) do
      room.memberships.create!(account: remote)
      room.messages.create!(account: remote, text: 'attachment').tap { |record| record.media_attachments << media }
    end

    def file_name
      described_class.message(ChatMessage.find(message.id), viewer: member).dig(:file, :name)
    end

    it 'comes from the declared type before the file is downloaded, not from the media ID, and stays the same after', :attachment_processing do
      expect(media.needs_redownload?).to be(true)
      expect(file_name).to eq('file.png')

      media.update!(file: fixture_file_upload('emojo.png', 'image/png'))

      expect(file_name).to eq('file.png')
    end

    it 'has no extension when the type is not known' do
      media.update_column(:file_content_type, nil)

      expect(file_name).to eq('file')
    end
  end

  it 'keeps the stored name of an attachment from this server' do
    media = Fabricate(:media_attachment, account: owner)
    message = room.messages.create!(account: owner, text: 'attachment')
    message.media_attachments << media

    expect(described_class.message(message, viewer: member).dig(:file, :name)).to eq(media.file_file_name)
  end

  it 'qualifies custom reactions by their server and supplies remote text emoji URLs' do
    remote = Fabricate(:account, domain: 'remote.example')
    room.memberships.create!(account: remote)
    emoji = Fabricate(:custom_emoji, shortcode: 'wave', domain: remote.domain)
    message = room.messages.create!(account: remote, text: ':wave:')
    message.reactions.create!(account: owner, reaction: '👍')
    other_message = room.messages.create!(account: owner, text: 'local')
    other_message.reactions.create!(account: remote, reaction: ':wave:')

    payload = described_class.message(message, viewer: member)
    reaction = described_class.message(other_message, viewer: member)[:reactions].first

    expect(payload[:emojis]['wave']).to include(emoji.image.url)
    expect(payload[:reactions]).to contain_exactly(include(user: include(id: mid(owner)), reaction: '👍'))
    expect(reaction).to include(reaction: ':wave@remote.example:', user: include(id: mid(remote)))
  end

  it 'does not expose text, attachments or reactions on a deleted message' do
    message = room.messages.create!(account: owner, text: 'private')
    message.reactions.create!(account: member, reaction: '👍')
    message.media_attachments << Fabricate(:media_attachment, account: owner)
    message.update!(deleted_at: Time.current)

    expect(described_class.message(message, viewer: member)).to include(text: nil, file: nil, fileId: nil, reactions: [], emojis: {})
  end
end
