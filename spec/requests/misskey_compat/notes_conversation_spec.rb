# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat notes/conversation' do
  let(:parent) { Fabricate(:status) }
  let(:status) { Fabricate(:status, in_reply_to_id: parent.id, in_reply_to_account_id: parent.account_id) }

  before { Setting.misskey_compat_enabled = true }
  after { Setting.misskey_compat_enabled = false }

  it 'rejects offsets above the traversal budget before loading ancestors' do
    queries = []
    callback = lambda do |_name, _started, _finished, _unique_id, payload|
      queries << payload[:sql] if payload[:name] != 'SCHEMA' && !payload[:cached]
    end

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      post '/api/notes/conversation', params: { noteId: MisskeyCompat::MiId.encode(status.id), offset: 1_001 }, as: :json
    end

    expect(response).to have_http_status(400)
    expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
    expect(response.parsed_body.dig(:error, :info, :param)).to eq('#/properties/offset')
    expect(queries.grep(/WITH RECURSIVE search_tree/)).to be_empty
  end

  it 'normalizes a negative offset to the first page' do
    post '/api/notes/conversation', params: { noteId: MisskeyCompat::MiId.encode(status.id), offset: -1 }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:id)).to contain_exactly(MisskeyCompat::MiId.encode(parent.id))
  end
end
