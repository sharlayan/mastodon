# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat notes and i parameter types' do
  let(:user)    { Fabricate(:user) }
  let(:account) { user.account }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def call(path, **body)
    post path, params: { i: token, **body }, as: :json
  end

  def expect_invalid_param(param = nil)
    expect(response).to have_http_status(400)
    expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
    expect(response.parsed_body.dig(:error, :info, :param)).to eq(param) if param
  end

  describe 'notes/create' do
    ['poll', 3, ['choice']].each do |poll|
      it "rejects poll #{poll.inspect}" do
        call('/api/notes/create', text: 'hello', poll: poll)

        expect_invalid_param('#/properties/poll')
        expect(account.statuses).to be_empty
      end
    end

    it 'rejects a non-scalar poll expiration' do
      call('/api/notes/create', text: 'hello', poll: { choices: %w(a b), expiredAfter: { x: 1 } })

      expect_invalid_param('#/properties/poll/properties/expiredAfter')
    end

    it 'rejects an out of range poll expiresAt' do
      call('/api/notes/create', text: 'hello', poll: { choices: %w(a b), expiresAt: 10**30 })

      expect_invalid_param('#/properties/poll/properties/expiresAt')
    end

    it 'rejects a non-scalar scheduledAt' do
      call('/api/notes/create', text: 'hello', scheduledAt: [1])

      expect_invalid_param('#/properties/scheduledAt')
    end

    it 'rejects an out of range scheduledAt' do
      call('/api/notes/create', text: 'hello', scheduledAt: 10**30)

      expect_invalid_param('#/properties/scheduledAt')
      expect(account.scheduled_statuses).to be_empty
    end

    it 'still schedules a valid scheduledAt' do
      call('/api/notes/create', text: 'hello', scheduledAt: 1.day.from_now.to_i * 1000)

      expect(response).to have_http_status(200)
      expect(account.scheduled_statuses.count).to eq(1)
    end

    it 'rejects an array renoteId' do
      quoted = Fabricate(:status)

      call('/api/notes/create', text: 'hello', renoteId: [quoted.id.to_s])

      expect_invalid_param('#/properties/renoteId')
    end
  end

  describe 'notes/drafts/create' do
    it 'rejects a string poll' do
      call('/api/notes/drafts/create', text: 'draft', poll: 'poll')

      expect_invalid_param('#/properties/poll')
      expect(account.status_drafts).to be_empty
    end
  end

  describe 'notes/drafts/list' do
    it 'rejects an out of range untilDate' do
      call('/api/notes/drafts/list', untilDate: 10**30)

      expect_invalid_param
    end

    it 'filters by a valid untilDate' do
      call('/api/notes/drafts/list', untilDate: 1.day.from_now.to_i * 1000)

      expect(response).to have_http_status(200)
    end
  end

  describe 'notes/polls/vote' do
    let(:poll_status) { Fabricate(:status, poll: Fabricate.build(:poll, options: %w(a b))) }

    [[0], { x: 0 }].each do |choice|
      it "rejects choice #{choice.inspect}" do
        call('/api/notes/polls/vote', noteId: MisskeyCompat::MiId.encode(poll_status.id), choice: choice)

        expect_invalid_param('#/properties/choice')
      end
    end

    it 'still accepts an integer choice' do
      call('/api/notes/polls/vote', noteId: MisskeyCompat::MiId.encode(poll_status.id), choice: 1)

      expect(response).to have_http_status(204)
    end
  end

  describe 'array note ids' do
    let(:note) { Fabricate(:status, account: account) }

    it 'rejects an array noteId for notes/show' do
      call('/api/notes/show', noteId: [note.id.to_s])

      expect_invalid_param('#/properties/noteId')
    end

    it 'rejects an array noteId for notes/update' do
      call('/api/notes/update', noteId: [note.id.to_s], text: 'changed')

      expect_invalid_param('#/properties/noteId')
      expect(note.reload.text).to_not eq('changed')
    end

    it 'rejects an array noteId for i/pin' do
      call('/api/i/pin', noteId: [note.id.to_s])

      expect_invalid_param('#/properties/noteId')
      expect(StatusPin.where(account: account)).to be_empty
    end
  end

  describe 'i/update' do
    it 'rejects non-object fields' do
      call('/api/i/update', fields: ['x'])

      expect_invalid_param('#/properties/fields')
    end

    it 'rejects non-object avatarDecorations' do
      call('/api/i/update', avatarDecorations: ['x'])

      expect_invalid_param('#/properties/avatarDecorations')
    end

    it 'still updates object fields' do
      call('/api/i/update', fields: [{ name: 'Site', value: 'example' }])

      expect(response).to have_http_status(200)
      expect(account.reload.fields.first.name).to eq('Site')
    end
  end
end
