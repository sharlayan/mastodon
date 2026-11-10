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

  def expect_invalid_param(param = nil, label = param)
    expect(response).to have_http_status(400), label
    expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM'), label
    expect(response.parsed_body.dig(:error, :info, :param)).to eq(param), label if param
  end

  describe 'notes/create' do
    it 'rejects malformed poll, poll expiration, scheduledAt, and renoteId values without creating statuses' do
      quoted = Fabricate(:status)
      [
        [{ poll: 'poll' }, '#/properties/poll'],
        [{ poll: 3 }, '#/properties/poll'],
        [{ poll: ['choice'] }, '#/properties/poll'],
        [{ poll: { choices: %w(a b), expiredAfter: { x: 1 } } }, '#/properties/poll/properties/expiredAfter'],
        [{ poll: { choices: %w(a b), expiresAt: 10**30 } }, '#/properties/poll/properties/expiresAt'],
        [{ scheduledAt: [1] }, '#/properties/scheduledAt'],
        [{ scheduledAt: 10**30 }, '#/properties/scheduledAt'],
        [{ renoteId: [quoted.id.to_s] }, '#/properties/renoteId'],
      ].each do |params, param|
        call('/api/notes/create', text: 'hello', **params)

        expect_invalid_param(param, params.inspect)
      end

      expect(account.statuses).to be_empty
      expect(account.scheduled_statuses).to be_empty
    end

    it 'still schedules a valid scheduledAt' do
      call('/api/notes/create', text: 'hello', scheduledAt: 1.day.from_now.to_i * 1000)

      expect(response).to have_http_status(200)
      expect(account.scheduled_statuses.count).to eq(1)
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
    it 'rejects an out of range untilDate and filters by a valid one' do
      call('/api/notes/drafts/list', untilDate: 10**30)

      expect_invalid_param

      call('/api/notes/drafts/list', untilDate: 1.day.from_now.to_i * 1000)

      expect(response).to have_http_status(200)
    end
  end

  describe 'notes/polls/vote' do
    let(:poll_status) { Fabricate(:status, poll: Fabricate.build(:poll, options: %w(a b))) }

    it 'rejects array and object choices and still accepts an integer choice' do
      [[0], { x: 0 }].each do |choice|
        call('/api/notes/polls/vote', noteId: MisskeyCompat::MiId.encode(poll_status.id), choice: choice)

        expect_invalid_param('#/properties/choice', choice.inspect)
      end

      call('/api/notes/polls/vote', noteId: MisskeyCompat::MiId.encode(poll_status.id), choice: 1)

      expect(response).to have_http_status(204)
    end
  end

  describe 'array note ids' do
    let(:note) { Fabricate(:status, account: account) }

    it 'rejects an array noteId for notes/show, notes/update, and i/pin' do
      call('/api/notes/show', noteId: [note.id.to_s])
      expect_invalid_param('#/properties/noteId', 'notes/show')

      call('/api/notes/update', noteId: [note.id.to_s], text: 'changed')
      expect_invalid_param('#/properties/noteId', 'notes/update')
      expect(note.reload.text).to_not eq('changed')

      call('/api/i/pin', noteId: [note.id.to_s])
      expect_invalid_param('#/properties/noteId', 'i/pin')
      expect(StatusPin.where(account: account)).to be_empty
    end
  end

  describe 'i/update' do
    it 'rejects non-object fields and avatarDecorations and still updates object fields' do
      call('/api/i/update', fields: ['x'])
      expect_invalid_param('#/properties/fields')

      call('/api/i/update', avatarDecorations: ['x'])
      expect_invalid_param('#/properties/avatarDecorations')

      call('/api/i/update', fields: [{ name: 'Site', value: 'example' }])

      expect(response).to have_http_status(200)
      expect(account.reload.fields.first.name).to eq('Site')
    end
  end
end
