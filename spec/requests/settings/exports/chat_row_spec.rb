# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings / Exports / Chat row' do
  let(:user) { Fabricate(:user) }

  before { sign_in user }

  after { Setting.chat_enabled = false }

  it 'says that chats come with the archive, and has no row while chat is disabled' do
    Setting.chat_enabled = true

    get '/settings/export'

    expect(response).to have_http_status(200)
    expect(response.body).to include(I18n.t('exports.chat_in_archive'))
    expect(response.body).to_not include('/settings/exports/chat')

    Setting.chat_enabled = false

    get '/settings/export'

    expect(response.body).to_not include(I18n.t('exports.chat_in_archive'))
  end
end
