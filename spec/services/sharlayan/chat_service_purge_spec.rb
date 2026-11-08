# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ChatService do
  include_context 'with an open chat policy'

  let(:service) { described_class.new }
  let(:owner) { Fabricate(:user).account }
  let(:departing) { Fabricate(:user).account }
  let(:staying) { Fabricate(:user).account }
  let(:room) { service.create_conversation(owner, type: :group, title: 'Room') }

  before do
    Setting.chat_enabled = true
    room.memberships.create!(account: departing)
    room.memberships.create!(account: staying)
  end

  after { Setting.chat_enabled = false }

  def unread_for(account)
    REST::ChatConversationSerializer.new(ChatConversation.find(room.id), current_account: account).as_json[:unread]
  end

  describe 'deleting an account whose message others last read' do
    let!(:earlier) { service.create_message(staying, room, text: 'from someone who stays') }

    before do
      service.create_message(departing, room, text: 'from someone who leaves')
      service.mark_read(owner, room)
    end

    it 'keeps the room read for the others' do
      service.purge_account(departing)

      expect(unread_for(owner)).to be(false)
      expect(room.memberships.find_by!(account: owner).last_read_message_id).to eq(earlier.id)
    end

    it 'still shows what arrived after the read message' do
      newer = service.create_message(staying, room, text: 'new')

      service.purge_account(departing)

      expect(unread_for(owner)).to be(true)
      expect(room.reload.last_message_id).to eq(newer.id)
    end
  end
end
