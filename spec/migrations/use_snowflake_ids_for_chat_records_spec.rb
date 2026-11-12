# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db', 'migrate', '20261113075600_use_snowflake_ids_for_chat_records.rb')

RSpec.describe UseSnowflakeIdsForChatRecords do
  let(:migration) { described_class.new }
  let(:connection) { ActiveRecord::Base.connection }
  let(:owner) { Fabricate(:account) }
  let(:invitee) { Fabricate(:account) }
  let(:room) { ChatConversation.create!(id: 42, conversation_type: :group, owner_account: owner, title: 'Legacy room') }
  let(:membership) { room.memberships.create!(account: owner) }
  let(:message) { room.messages.create!(account: owner, text: 'Legacy message') }
  let(:records) do
    provider = Fabricate(:voice_relay_provider)
    [
      membership,
      message,
      message.edits.create!(text: 'Original text'),
      message.reactions.create!(account: owner, reaction: '👍'),
      message.chat_message_media_attachments.create!(media_attachment: Fabricate(:media_attachment, account: owner)),
      room.invitations.create!(inviter_account: owner, invitee_account: invitee),
      room.roster_states.find_by!(account: owner),
      provider,
      VoiceCallAllocation.create!(chat_conversation: room, voice_relay_provider: provider, room_key: 'legacy', generation: 'legacy', slots: 2),
      VoiceCallRemoteSession.create!(account: owner, chat_conversation: room, identity: 'legacy', room_name: 'legacy', origin: 'https://remote.example', expires_at: 1.hour.from_now),
      VoiceCallRemoteState.create!(chat_conversation: room, remote_updated_at: Time.now.to_i),
    ]
  end

  before do
    migration.down
    membership
    room.update!(last_message: message)
    membership.update!(last_read_message: message)
  end

  it 'changes only new IDs and preserves chat and voice references through rollback and reapplication' do
    snapshots = records.map(&:attributes)

    migration.up
    migration.up

    expect(records.map { |record| record.reload.attributes }).to eq(snapshots)
    expect(room.reload).to have_attributes(id: 42, last_message_id: message.id)
    expect(membership.reload.last_read_message_id).to eq(message.id)

    expect_snowflake_defaults

    reply = room.messages.create!(account: owner, text: 'New message', reply_to: message)
    expect(reply.id).to be > (1 << 53)
    expect(Mastodon::Snowflake.to_time(reply.id)).to be_within(1.minute).of(Time.now.utc)
    expect(room.messages.order(id: :desc).pluck(:id)).to eq([reply.id, message.id])
    expect(reply.reply_to_id).to eq(message.id)

    migration.down

    expect(records.map { |record| record.reload.attributes }).to eq(snapshots)
    expect(reply.reload.reply_to_id).to eq(message.id)
    expect_sequential_defaults

    migration.up
  end

  def expect_snowflake_defaults
    tables = connection.tables.grep(/\A(chat_|voice_)/) - ['chat_conversations']
    expect(described_class::TABLES).to match_array(tables)

    tables.each do |table|
      default = connection.columns(table).find { |column| column.name == 'id' }.default_function
      expect(default).to eq("timestamp_id('#{table}'::text)")
      expect(Mastodon::Snowflake.to_time(connection.select_value("SELECT #{default}"))).to be_within(1.minute).of(Time.now.utc)
    end
  end

  def expect_sequential_defaults
    described_class::TABLES.each do |table|
      expect(connection.columns(table).find { |column| column.name == 'id' }.default_function).to eq("nextval('#{table}_id_seq'::regclass)")
    end
  end
end
