# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ChatBroadcastPayload do
  let(:owner) { Fabricate(:user).account }
  let(:members) { Array.new(3) { Fabricate(:user).account } }
  let(:room) do
    ChatConversation.create!(conversation_type: :group, owner_account: owner, title: 'Room').tap do |record|
      record.memberships.create!(account: owner, role: :owner)
      members.each { |member| record.memberships.create!(account: member) }
    end
  end
  let(:message) { room.messages.create!(account: owner, text: 'hello') }

  before do
    freeze_time
    room.update!(last_message: message)
  end

  context 'with a message' do
    it 'renders a message only once however many viewers there are, as the serializer does for each viewer' do
      allow(REST::ChatMessageSerializer).to receive(:new).and_call_original
      payload = described_class.new(message, REST::ChatMessageSerializer)

      rendered = members.map { |viewer| payload.for(viewer).as_json }

      expect(REST::ChatMessageSerializer).to have_received(:new).once
      expect(rendered).to eq(members.map { |viewer| REST::ChatMessageSerializer.new(message, current_account: viewer).as_json.as_json })
    end
  end

  context 'with a message with attachments' do
    let(:media) { Array.new(2) { Fabricate(:media_attachment, account: owner, status: nil) } }

    before do
      media.each { |attachment| message.chat_message_media_attachments.create!(media_attachment: attachment) }
      message.reload
    end

    it 'renders the rest of the message only once without looking up the attachments again, giving each viewer their own attachment addresses' do
      allow(REST::ChatMessageSerializer).to receive(:new).and_call_original
      payload = described_class.new(message, REST::ChatMessageSerializer)
      payload.for(members.first)
      queries = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') { |*, details| queries << details[:sql] }

      rendered = members.map { |viewer| payload.for(viewer).as_json }

      ActiveSupport::Notifications.unsubscribe(subscriber)
      expect(queries.grep(/chat_message_media_attachments/)).to be_empty
      expect(REST::ChatMessageSerializer).to have_received(:new).once
      expect(rendered.flat_map { |json| json['media_attachments'].pluck('url') }.uniq.size).to eq(members.size * media.size)
      expect(rendered).to eq(members.map { |viewer| REST::ChatMessageSerializer.new(message, current_account: viewer).as_json.as_json })
    end
  end

  context 'with a conversation' do
    before do
      room.memberships.find_by!(account: members.first).update!(muted: true, last_read_message: message)
      room.reload
    end

    it 'renders the member list only once however many viewers there are, as the serializer does for each viewer' do
      allow(REST::AccountSerializer).to receive(:new).and_call_original
      payload = described_class.new(room, REST::ChatConversationSerializer)

      members.each { |viewer| payload.for(viewer) }

      expect(REST::AccountSerializer).to have_received(:new).exactly(room.accounts.size + 1).times
      expect(payload.for(owner)).to include(current_role: 'owner', muted: false)
      expect(payload.for(members.first)).to include(current_role: 'member', muted: true, unread: false)
      expect(payload.for(members.last)).to include(current_role: 'member', muted: false, unread: true)
      expect([owner, *members].map { |viewer| payload.for(viewer).as_json })
        .to eq([owner, *members].map { |viewer| REST::ChatConversationSerializer.new(room, current_account: viewer).as_json.as_json })
    end
  end

  it 'passes an object without a serializer through' do
    expect(described_class.new({ id: '1' }, nil).for(owner)).to eq({ id: '1' })
  end

  it 'still renders other serializers for each viewer' do
    reaction = message.reactions.create!(account: members.first, reaction: '👍')

    expect(described_class.new(reaction, REST::ChatMessageReactionSerializer).for(owner).as_json)
      .to eq(REST::ChatMessageReactionSerializer.new(reaction, current_account: owner).as_json.as_json)
  end
end
