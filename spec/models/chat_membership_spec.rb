# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChatMembership do
  describe 'account deletion cleanup' do
    let(:owner) { Fabricate(:account) }
    let(:member) { Fabricate(:account) }

    it 'removes a direct conversation when either account is deleted' do
      conversation = ChatConversation.create!(conversation_type: :direct, direct_key: [owner.id, member.id].sort.join(':'))
      conversation.memberships.create!([{ account: owner }, { account: member }])

      owner.destroy!

      expect(ChatConversation).to_not exist(conversation.id)
    end

    it 'removes a group conversation when its owner account is deleted' do
      conversation = ChatConversation.create!(conversation_type: :group, owner_account: owner, title: 'Group')
      conversation.memberships.create!(account: owner, role: :owner)
      conversation.memberships.create!(account: member)

      owner.destroy!

      expect(ChatConversation).to_not exist(conversation.id)
    end

    it 'keeps a group conversation when a regular member account is deleted' do
      conversation = ChatConversation.create!(conversation_type: :group, owner_account: owner, title: 'Group')
      conversation.memberships.create!(account: owner, role: :owner)
      conversation.memberships.create!(account: member)

      member.destroy!

      expect(ChatConversation).to exist(conversation.id)
      expect(conversation.reload.accounts).to contain_exactly(owner)
    end
  end
end
