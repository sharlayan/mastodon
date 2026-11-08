# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Chat' do
  include_context 'with an open chat policy'

  include_context 'with API authentication', oauth_scopes: 'read write'

  let!(:user) { Fabricate(:user, account_attributes: { username: 'alice' }) }
  let!(:other) { Fabricate(:user, account_attributes: { username: 'bob' }) }
  let!(:third) { Fabricate(:user, account_attributes: { username: 'carol' }) }

  around { |example| ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') { example.run } }

  before do
    Setting.chat_enabled = true
    Setting.chat_soft_delete_enabled = false
    Setting.chat_delete_window_hours = 24
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_soft_delete_enabled = false
    Setting.chat_delete_window_hours = 24
  end

  it 'returns not found while the server feature is disabled' do
    Setting.chat_enabled = false

    get '/api/v1/chat/conversations', headers: headers

    expect(response).to have_http_status(404)
  end

  it 'does not allow a read-only token to mutate chat data' do
    token.update!(scopes: 'read')

    post '/api/v1/chat/conversations', params: { type: 'direct', account_ids: [other.account.id] }, headers: headers

    expect(response).to have_http_status(403)
    expect(ChatConversation.count).to be_zero
  end

  it 'does not allow a write-only token to read chat data' do
    token.update!(scopes: 'write')

    get '/api/v1/chat/conversations', headers: headers

    expect(response).to have_http_status(403)
  end

  it 'tells the client when a deletion only hides the message' do
    Setting.chat_delete_window_hours = 6
    get '/api/v1/chat/settings', headers: headers
    expect(response.parsed_body).to include(delete_window_hours: 6, soft_delete: false)

    allow(RoleplayModeHelper).to receive(:roleplay_mode?).and_return(true)
    get '/api/v1/chat/settings', headers: headers
    expect(response.parsed_body).to include(soft_delete: true)
  ensure
    Setting.chat_delete_window_hours = 24
  end

  it 'updates personal chat policy settings' do
    patch '/api/v1/chat/settings', params: { policy: 'none', allow_group_invites: false, notifications: false }, headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(policy: 'none', allow_group_invites: false, notifications: false)
    expect(user.reload.settings[:chat_policy]).to eq('none')
  end

  it 'paginates conversations in last-message order instead of creation order' do
    service = Sharlayan::ChatService.new
    older_room = service.create_conversation(user.account, type: :group, title: 'Older room')
    newer_room = service.create_conversation(user.account, type: :group, title: 'Newer room')
    service.create_message(user.account, newer_room, text: 'earlier')
    service.create_message(user.account, older_room, text: 'latest')

    get '/api/v1/chat/conversations', params: { limit: 1 }, headers: headers
    expect(response.parsed_body.pluck(:id)).to eq([older_room.id.to_s])

    get '/api/v1/chat/conversations', params: { limit: 1, max_id: older_room.id }, headers: headers
    expect(response.parsed_body.pluck(:id)).to eq([newer_room.id.to_s])
  end

  it 'does not count read markers against the chat write rate limit' do
    conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :group, title: 'Group')
    allow(RateLimiter).to receive(:new).and_call_original

    post "/api/v1/chat/conversations/#{conversation.id}/read", headers: headers

    expect(response).to have_http_status(200)
    expect(RateLimiter).to_not have_received(:new).with(user.account, family: :chat_writes)
  end

  describe 'direct chat' do
    it 'creates one conversation per local account pair' do
      post '/api/v1/chat/conversations', params: { type: 'direct', account_ids: [other.account.id] }, headers: headers
      first_id = response.parsed_body[:id]

      post '/api/v1/chat/conversations', params: { type: 'direct', account_ids: [other.account.id] }, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:id]).to eq(first_id)
      expect(ChatConversation.chat_direct.count).to eq(1)
    end

    it 'continues to accept the current account in the participant array' do
      post '/api/v1/chat/conversations', params: { type: 'direct', account_ids: [user.account.id, other.account.id] }, headers: headers

      expect(response).to have_http_status(200)
      expect(ChatConversation.chat_direct.count).to eq(1)
    end

    it 'enforces the recipient direct chat policy for new conversations' do
      other.settings[:chat_policy] = 'none'
      other.save!

      post '/api/v1/chat/conversations', params: { type: 'direct', account_ids: [other.account.id] }, headers: headers

      expect(response).to have_http_status(403)
      expect(ChatConversation.count).to be_zero
    end

    it 'rejects a direct conversation when either account blocks the other' do
      other.account.block!(user.account)

      post '/api/v1/chat/conversations', params: { type: 'direct', account_ids: [other.account.id] }, headers: headers

      expect(response).to have_http_status(403)
      expect(ChatConversation.count).to be_zero
    end

    it 'rejects new messages after either direct participant blocks the other' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :direct, account_ids: [other.account.id])
      user.account.block!(other.account)

      post "/api/v1/chat/conversations/#{conversation.id}/messages", params: { text: 'blocked' }, headers: headers

      expect(response).to have_http_status(403)
      expect(conversation.messages).to be_empty
    end

    it 'rejects edits and new reactions after either direct participant blocks the other' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :direct, account_ids: [other.account.id])
      message = Sharlayan::ChatService.new.create_message(user.account, conversation, text: 'before block')
      other.account.block!(user.account)

      patch "/api/v1/chat/messages/#{message.id}", params: { text: 'after block' }, headers: headers
      edit_status = response.status
      post "/api/v1/chat/messages/#{message.id}/reactions", params: { reaction: '👍' }, headers: headers

      expect(edit_status).to eq(403)
      expect(response).to have_http_status(403)
      expect(message.reload.text).to eq('before block')
      expect(message.reactions).to be_empty
    end

    it 'creates, lists, and reads messages' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :direct, account_ids: [other.account.id])

      post "/api/v1/chat/conversations/#{conversation.id}/messages", params: { text: 'hello' }, headers: headers
      message_id = response.parsed_body[:id]
      get "/api/v1/chat/conversations/#{conversation.id}/messages", headers: headers
      post "/api/v1/chat/conversations/#{conversation.id}/read", params: { message_id: message_id }, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:last_read_message_id]).to eq(message_id)
      expect(conversation.messages.first.text).to eq('hello')
    end

    it 'does not expose a conversation to a non-member' do
      conversation = Sharlayan::ChatService.new.create_conversation(other.account, type: :direct, account_ids: [third.account.id])

      get "/api/v1/chat/conversations/#{conversation.id}", headers: headers

      expect(response).to have_http_status(404)
    end

    it 'attaches owned unattached media to a message' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :direct, account_ids: [other.account.id])
      media = Fabricate(:media_attachment, account: user.account, status: nil)

      post "/api/v1/chat/conversations/#{conversation.id}/messages", params: { media_ids: [media.id] }, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:media_attachments].pluck(:id)).to contain_exactly(media.id.to_s)
      expect(conversation.messages.last.media_attachments).to contain_exactly(media)
    end

    it 'rejects media owned by another account' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :direct, account_ids: [other.account.id])
      media = Fabricate(:media_attachment, account: other.account, status: nil)

      post "/api/v1/chat/conversations/#{conversation.id}/messages", params: { media_ids: [media.id] }, headers: headers

      expect(response).to have_http_status(422)
      expect(conversation.messages).to be_empty
    end

    it 'issues an expiring attachment URL that remains bound to the chat member' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :group, title: 'Group')
      conversation.memberships.create!(account: other.account)
      media = Fabricate(:media_attachment, account: user.account, status: nil)
      message = Sharlayan::ChatService.new.create_message(user.account, conversation, text: nil, media_ids: [media.id])
      token.update!(resource_owner_id: other.id)

      get "/api/v1/chat/messages/#{message.id}", headers: headers
      attachment_url = response.parsed_body.fetch(:media_attachments).first.fetch(:url)
      attachment_path = URI.parse(attachment_url).request_uri

      expect(attachment_url).to include('chat_token=')
      get attachment_path
      expect(response).to have_http_status(:redirect)

      conversation.memberships.find_by!(account: other.account).destroy!
      get attachment_path
      expect(response).to have_http_status(404)
    end

    it 'rejects tampered and expired chat attachment capabilities' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :direct, account_ids: [other.account.id])
      media = Fabricate(:media_attachment, account: user.account, status: nil)
      message = Sharlayan::ChatService.new.create_message(user.account, conversation, text: nil, media_ids: [media.id])
      token.update!(resource_owner_id: other.id)

      get "/api/v1/chat/messages/#{message.id}", headers: headers
      attachment_path = URI.parse(response.parsed_body.fetch(:media_attachments).first.fetch(:url)).request_uri

      get attachment_path.sub(/chat_token=[^&]+/, 'chat_token=invalid')
      expect(response).to have_http_status(404)

      travel 11.minutes do
        get attachment_path
        expect(response).to have_http_status(404)
      end
    end

    it 'prevents a non-member from reacting to a message' do
      conversation = Sharlayan::ChatService.new.create_conversation(other.account, type: :direct, account_ids: [third.account.id])
      message = Sharlayan::ChatService.new.create_message(other.account, conversation, text: 'private')

      post "/api/v1/chat/messages/#{message.id}/reactions", params: { reaction: '👍' }, headers: headers

      expect(response).to have_http_status(404)
      expect(message.reactions).to be_empty
    end

    it 'does not allow reactions on a deleted message' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :direct, account_ids: [other.account.id])
      message = Sharlayan::ChatService.new.create_message(other.account, conversation, text: 'delete me')
      Sharlayan::ChatService.new.delete_message(other.account, message)

      post "/api/v1/chat/messages/#{message.id}/reactions", params: { reaction: '👍' }, headers: headers

      expect(response).to have_http_status(422)
      expect(message.reactions).to be_empty
    end

    it 'searches only messages visible to the current account' do
      visible_conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :direct, account_ids: [other.account.id])
      hidden_conversation = Sharlayan::ChatService.new.create_conversation(other.account, type: :direct, account_ids: [third.account.id])
      visible_message = Sharlayan::ChatService.new.create_message(user.account, visible_conversation, text: 'shared needle')
      Sharlayan::ChatService.new.create_message(other.account, hidden_conversation, text: 'private needle')

      get '/api/v1/chat/messages/search', params: { q: 'needle' }, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to contain_exactly(visible_message.id.to_s)
    end

    it 'stores a per-conversation mute preference' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :direct, account_ids: [other.account.id])

      post "/api/v1/chat/conversations/#{conversation.id}/mute", headers: headers

      expect(response).to have_http_status(200)
      expect(conversation.memberships.find_by!(account: user.account)).to be_muted
    end
  end

  describe 'group chat' do
    it 'creates invitations and admits an invited account' do
      post '/api/v1/chat/conversations', params: { type: 'group', title: 'Group', account_ids: [other.account.id] }, headers: headers
      conversation = ChatConversation.find(response.parsed_body[:id])
      invitation = conversation.invitations.find_by!(invitee_account: other.account)

      token.update!(resource_owner_id: other.id)
      post "/api/v1/chat/invitations/#{invitation.id}/accept", headers: headers

      expect(response).to have_http_status(200)
      expect(conversation.memberships.exists?(account: other.account)).to be true
      expect(invitation.reload).to be_accepted
    end

    it 'prevents members from inviting another account' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :group, account_ids: [], title: 'Group')
      conversation.memberships.create!(account: other.account)
      token.update!(resource_owner_id: other.id)

      post "/api/v1/chat/conversations/#{conversation.id}/invitations", params: { account_id: third.account.id }, headers: headers

      expect(response).to have_http_status(403)
    end

    it 'prevents an owner from inviting an account blocked in either direction' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :group, account_ids: [], title: 'Group')
      third.account.block!(user.account)

      post "/api/v1/chat/conversations/#{conversation.id}/invitations", params: { account_id: third.account.id }, headers: headers

      expect(response).to have_http_status(403)
      expect(conversation.invitations).to be_empty
    end

    it 'prevents accepting an invitation when a block was added after it was sent' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :group, account_ids: [other.account.id], title: 'Group')
      invitation = conversation.invitations.find_by!(invitee_account: other.account)
      other.account.block!(user.account)
      token.update!(resource_owner_id: other.id)

      post "/api/v1/chat/invitations/#{invitation.id}/accept", headers: headers

      expect(response).to have_http_status(403)
      expect(conversation.memberships.exists?(account: other.account)).to be false
    end

    it 'allows only the inviter to cancel a pending invitation' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :group, account_ids: [other.account.id], title: 'Group')
      invitation = conversation.invitations.find_by!(invitee_account: other.account)

      delete "/api/v1/chat/invitations/#{invitation.id}", headers: headers

      expect(response).to have_http_status(200)
      expect(invitation.reload).to be_cancelled
    end

    it 'does not let the invitee cancel a pending invitation' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :group, account_ids: [other.account.id], title: 'Group')
      invitation = conversation.invitations.find_by!(invitee_account: other.account)
      token.update!(resource_owner_id: other.id)

      delete "/api/v1/chat/invitations/#{invitation.id}", headers: headers

      expect(response).to have_http_status(403)
      expect(invitation.reload).to be_pending
    end

    it 'removes attachments and reactions when a message is soft-deleted' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :group, account_ids: [], title: 'Group')
      media = Fabricate(:media_attachment, account: user.account, status: nil)
      first_message = Sharlayan::ChatService.new.create_message(user.account, conversation, text: nil, media_ids: [media.id])
      first_message.reactions.create!(account: user.account, reaction: '👍')

      delete "/api/v1/chat/messages/#{first_message.id}", headers: headers
      post "/api/v1/chat/conversations/#{conversation.id}/messages", params: { media_ids: [media.id] }, headers: headers

      expect(response).to have_http_status(422)
      expect(first_message.reload.media_attachments).to be_empty
      expect(first_message.reactions).to be_empty
      expect(MediaAttachment.exists?(media.id)).to be(false)
    end

    it 'hides messages only from the sender after the deletion window expires' do
      Setting.chat_delete_window_hours = 24
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :direct, account_ids: [other.account.id])
      message = Sharlayan::ChatService.new.create_message(user.account, conversation, text: 'retained')
      message.update_column(:created_at, 25.hours.ago)

      delete "/api/v1/chat/messages/#{message.id}", headers: headers
      get "/api/v1/chat/conversations/#{conversation.id}/messages", headers: headers
      sender_messages = response.parsed_body
      token.update!(resource_owner_id: other.id)
      get "/api/v1/chat/conversations/#{conversation.id}/messages", headers: headers

      expect(message.reload).to have_attributes(text: 'retained', deleted_at: nil)
      expect(message.hidden_at).to be_present
      expect(sender_messages).to be_empty
      expect(response.parsed_body.pluck('id')).to include(message.id.to_s)
    ensure
      Setting.chat_delete_window_hours = 24
    end

    it 'always hides instead of deleting when chat preservation is enabled' do
      Setting.chat_soft_delete_enabled = true
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :direct, account_ids: [other.account.id])
      message = Sharlayan::ChatService.new.create_message(user.account, conversation, text: 'retained')

      delete "/api/v1/chat/messages/#{message.id}", headers: headers

      expect(message.reload).to have_attributes(text: 'retained', deleted_at: nil)
      expect(message.hidden_at).to be_present
    ensure
      Setting.chat_soft_delete_enabled = false
    end

    it 'always hides instead of deleting in roleplay mode' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :direct, account_ids: [other.account.id])
      message = Sharlayan::ChatService.new.create_message(user.account, conversation, text: 'retained')

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
        delete "/api/v1/chat/messages/#{message.id}", headers: headers
      end

      expect(message.reload).to have_attributes(text: 'retained', deleted_at: nil)
      expect(message.hidden_at).to be_present
    end

    it 'does not allow chat media to be reused in a post, status update, or status draft' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :group, account_ids: [], title: 'Group')
      media = Fabricate(:media_attachment, account: user.account, status: nil)
      Sharlayan::ChatService.new.create_message(user.account, conversation, text: nil, media_ids: [media.id])
      status = Fabricate(:status, account: user.account)

      post '/api/v1/statuses', params: { status: 'public', media_ids: [media.id] }, headers: headers
      post_status = response.status
      put "/api/v1/statuses/#{status.id}", params: { status: 'updated', media_ids: [media.id] }, headers: headers
      update_status = response.status
      post '/api/v1/status_drafts', params: { status: 'draft', media_ids: [media.id] }, headers: headers

      expect(post_status).to eq(422)
      expect(update_status).to eq(422)
      expect(response).to have_http_status(404)
      expect(media.reload).to have_attributes(status_id: nil, status_draft_id: nil)
    end

    it 'makes archived groups read-only until the owner unarchives them' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :group, account_ids: [], title: 'Group')

      post "/api/v1/chat/conversations/#{conversation.id}/archive", headers: headers
      post "/api/v1/chat/conversations/#{conversation.id}/messages", params: { text: 'archived' }, headers: headers
      message_status = response.status
      patch "/api/v1/chat/conversations/#{conversation.id}", params: { title: 'Changed' }, headers: headers

      expect(message_status).to eq(422)
      expect(response).to have_http_status(422)
      expect(conversation.reload.title).to eq('Group')
      expect(conversation.messages).to be_empty
    end

    it 'allows the owner to update active group details' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :group, account_ids: [], title: 'Group')

      patch "/api/v1/chat/conversations/#{conversation.id}", params: { title: 'Renamed', description: 'Updated description' }, headers: headers

      expect(response).to have_http_status(200)
      expect(conversation.reload).to have_attributes(title: 'Renamed', description: 'Updated description')
    end

    it 'enforces the group member limit for later invitations' do
      Setting.chat_max_group_members = 2
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :group, account_ids: [other.account.id], title: 'Group')

      post "/api/v1/chat/conversations/#{conversation.id}/invitations", params: { account_id: third.account.id }, headers: headers

      expect(response).to have_http_status(422)
      expect(conversation.invitations.pending.pluck(:invitee_account_id)).to contain_exactly(other.account.id)
    ensure
      Setting.chat_max_group_members = 50
    end

    it 'rejects oversized participant arrays before creating a group' do
      account_ids = Array.new(Setting.chat_max_group_members) { |index| (10_000_000 + index).to_s }

      post '/api/v1/chat/conversations', params: { type: 'group', title: 'Group', account_ids: account_ids }, headers: headers

      expect(response).to have_http_status(422)
      expect(ChatConversation).to_not exist
    end

    it 'rechecks the group member limit when accepting an invitation' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :group, account_ids: [], title: 'Group')
      conversation.memberships.create!(account: third.account)
      invitation = conversation.invitations.create!(inviter_account: user.account, invitee_account: other.account)
      Setting.chat_max_group_members = 2
      token.update!(resource_owner_id: other.id)

      post "/api/v1/chat/invitations/#{invitation.id}/accept", headers: headers

      expect(response).to have_http_status(422)
      expect(invitation.reload).to be_pending
      expect(conversation.memberships.exists?(account: other.account)).to be false
    ensure
      Setting.chat_max_group_members = 50
    end

    it 'does not reveal invitations to unrelated accounts' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :group, account_ids: [other.account.id], title: 'Group')
      invitation = conversation.invitations.find_by!(invitee_account: other.account)
      token.update!(resource_owner_id: third.id)

      post "/api/v1/chat/invitations/#{invitation.id}/reject", headers: headers

      expect(response).to have_http_status(404)
      expect(invitation.reload).to be_pending
    end
  end

  it 'rejects oversized message search queries' do
    get '/api/v1/chat/messages/search', params: { q: 'a' * 201 }, headers: headers

    expect(response).to have_http_status(400)
  end

  describe 'remote chat support' do
    let!(:remote) do
      Fabricate(:account,
                domain: 'remote.test',
                uri: 'https://remote.test/users/remote',
                inbox_url: 'https://remote.test/users/remote/inbox',
                can_chat: true,
                chat_scope: 'everyone')
    end

    before do
      Setting.chat_federation_enabled = true
    end

    after do
      Setting.chat_federation_enabled = false
    end

    it 'creates a direct conversation with a remote account' do
      post '/api/v1/chat/conversations', params: { type: 'direct', account_ids: [remote.id] }, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:accounts].pluck(:id)).to include(remote.id.to_s)
      expect(response.parsed_body[:remote]).to be(true)
    end

    it 'accepts mutual and none policy values and normalizes legacy values' do
      patch '/api/v1/chat/settings', params: { policy: 'mutual' }, headers: headers
      expect(response).to have_http_status(200)
      expect(user.reload.settings[:chat_policy]).to eq('mutual')

      patch '/api/v1/chat/settings', params: { policy: 'nobody' }, headers: headers
      expect(response).to have_http_status(200)
      expect(user.reload.settings[:chat_policy]).to eq('none')
    end

    it 'redistributes the actor when the chat policy changes' do
      expect { patch '/api/v1/chat/settings', params: { policy: 'none' }, headers: headers }
        .to change(ActivityPub::UpdateDistributionWorker.jobs, :size).by(1)
    end

    it 'does not redistribute the actor when the chat policy stays the same' do
      user.settings[:chat_policy] = 'none'
      user.save!

      expect { patch '/api/v1/chat/settings', params: { policy: 'none', notifications: false }, headers: headers }
        .to_not change(ActivityPub::UpdateDistributionWorker.jobs, :size)
    end

    it 'invites a remote account and federates the invitation' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :group, account_ids: [], title: 'Remote group')

      expect do
        post "/api/v1/chat/conversations/#{conversation.id}/invitations", params: { account_id: remote.id }, headers: headers
      end.to change(ActivityPub::DeliveryWorker.jobs, :size).by(1)

      expect(response).to have_http_status(200)
      expect(conversation.invitations.pending.find_by(invitee_account: remote)).to be_present
    end

    it 'does not list an invitation from a suspended account' do
      owner = Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/owner', inbox_url: 'https://remote.test/users/owner/inbox')
      room = ChatConversation.create!(conversation_type: :group, owner_account: owner, title: 'Room', uri: 'https://remote.test/chat/rooms/1')
      room.memberships.create!(account: owner, role: :owner)
      room.invitations.create!(inviter_account: owner, invitee_account: user.account)
      owner.suspend!

      get '/api/v1/chat/invitations', headers: headers
      expect(response.parsed_body).to be_empty

      owner.unsuspend!

      get '/api/v1/chat/invitations', headers: headers
      expect(response.parsed_body.size).to eq(1)
    end

    it 'rejects attachments over the limit' do
      conversation = Sharlayan::ChatService.new.create_conversation(user.account, type: :direct, account_ids: [other.account.id])
      media = Array.new(5) { Fabricate(:media_attachment, account: user.account, status: nil) }

      post "/api/v1/chat/conversations/#{conversation.id}/messages", params: { media_ids: media.map(&:id) }, headers: headers

      expect(response).to have_http_status(422)
      expect(conversation.messages).to be_empty
    end
  end
end
