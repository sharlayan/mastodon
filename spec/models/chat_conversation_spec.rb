# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChatConversation do
  let(:owner) { Fabricate(:user).account }
  let(:member) { Fabricate(:user).account }

  def room_with_messages(count)
    described_class.create!(conversation_type: :group, owner_account: owner, title: 'Room').tap do |room|
      room.memberships.create!(account: owner, role: :owner)
      room.memberships.create!(account: member)
      count.times do |index|
        message = room.messages.create!(account: owner, text: "message #{index}")
        message.reactions.create!(account: member, reaction: '👍')
        message.edits.create!(text: 'before')
        room.update!(last_message: message)
      end
    end
  end

  def queries_during
    sql = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') { |*, payload| sql << payload[:sql] unless payload[:name] == 'SCHEMA' || payload[:cached] }
    yield
    sql
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  describe '#destroy!' do
    it 'does not query once for every message' do
      small = room_with_messages(2)
      large = room_with_messages(20)

      few = queries_during { small.destroy! }.size
      many = queries_during { large.destroy! }.size

      expect(many).to eq(few)
    end

    it 'removes messages with their reactions, edits and attachment links' do
      room = room_with_messages(3)
      message_ids = room.messages.pluck(:id)

      room.destroy!

      expect(ChatMessage.where(id: message_ids)).to be_empty
      expect(ChatMessageReaction.where(chat_message_id: message_ids)).to be_empty
      expect(ChatMessageEdit.where(chat_message_id: message_ids)).to be_empty
    end

    it 'removes attachments used only by the chat right away' do
      room = room_with_messages(0)
      media = Fabricate(:media_attachment, account: owner, status: nil)
      message = room.messages.create!(account: owner, text: 'look', pending_media_attachments: [media])
      message.chat_message_media_attachments.create!(media_attachment: media)

      room.destroy!

      expect(MediaAttachment).to_not exist(media.id)
    end

    it 'removes many attachments in the background', :inline_jobs do
      stub_const('ChatMediaRemovalWorker::INLINE_LIMIT', 0)
      room = room_with_messages(0)
      media = Fabricate(:media_attachment, account: owner, status: nil)
      message = room.messages.create!(account: owner, text: 'look', pending_media_attachments: [media])
      message.chat_message_media_attachments.create!(media_attachment: media)

      room.destroy!

      expect(MediaAttachment).to_not exist(media.id)
    end

    it 'keeps an attachment that came to be used by a post before the background removal' do
      stub_const('ChatMediaRemovalWorker::INLINE_LIMIT', 0)
      room = room_with_messages(0)
      media = Fabricate(:media_attachment, account: owner, status: nil)
      message = room.messages.create!(account: owner, text: 'look', pending_media_attachments: [media])
      message.chat_message_media_attachments.create!(media_attachment: media)

      room.destroy!
      media.update!(status: Fabricate(:status, account: owner))
      ChatMediaRemovalWorker.drain

      expect(MediaAttachment).to exist(media.id)
    end
  end
end
