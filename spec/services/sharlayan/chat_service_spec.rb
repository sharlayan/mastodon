# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ChatService do
  describe '#mark_read' do
    it 'broadcasts only when the read pointer advances' do
      account = Fabricate(:user).account
      other_account = Fabricate(:user).account
      conversation = described_class.new.create_conversation(account, type: :direct, account_ids: [other_account.id])
      message = described_class.new.create_message(other_account, conversation, text: 'hello')
      service = described_class.new
      allow(service).to receive(:broadcast_to)

      service.mark_read(account, conversation, message_id: message.id)
      service.mark_read(account, conversation, message_id: message.id)

      expect(service).to have_received(:broadcast_to).once
    end
  end
end
