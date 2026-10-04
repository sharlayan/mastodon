# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompat::UserCollectionContext, type: :request do
  let(:viewer) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: viewer.id, scopes: 'read').token }

  before do
    Setting.misskey_compat_enabled = true
    Setting.pages_enabled = true
  end

  after do
    Setting.misskey_compat_enabled = false
    Setting.pages_enabled = false
  end

  it 'batches main page attachments and likes while preserving their JSON' do
    accounts = Array.new(2) { Fabricate(:account) }
    main_pages = accounts.each_with_index.map { |account, index| create_main_page(account, mixed_ids: index.zero?) }
    pages = main_pages.pluck(:page)
    PageLike.create!(account: viewer.account, page: pages.first)
    ids = accounts.map { |account| MisskeyCompat::MiId.encode(account.id) }
    queries = []
    callback = ->(_name, _started, _finished, _id, payload) { queries << payload[:sql] if payload[:name] != 'SCHEMA' && !payload[:cached] }

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      post '/api/users/show', params: { i: token, userIds: ids }, as: :json
    end

    expect(response).to have_http_status(200)
    responses_by_id = response.parsed_body.index_by { |item| item[:id] }
    main_pages.each_with_index { |main_page, index| expect_pinned_page(responses_by_id.fetch(ids[index]), main_page, liked: index.zero?) }
    expect(queries.count { |sql| sql.include?('FROM "media_attachments"') }).to eq(1)
    expect(queries.count { |sql| sql.include?('FROM "page_likes"') }).to eq(1)
  end

  def create_main_page(account, mixed_ids:)
    media = Array.new(2) { Fabricate(:media_attachment, account: account) }
    file_ids = mixed_ids ? [media.second.id, media.second.id.to_s, media.first.id.to_s] : [media.first.id.to_s]
    content = file_ids.map.with_index { |file_id, index| { 'id' => "image-#{index}", 'type' => 'image', 'fileId' => file_id } }
    page = Fabricate(:page, account: account, is_main: true, content: [{ 'id' => 'image', 'type' => 'image', 'fileId' => media.first.id.to_s }])
    page.update_column(:content, content) if mixed_ids
    { page: page, media: mixed_ids ? media : [media.first], file_ids: file_ids }
  end

  def expect_pinned_page(response, main_page, liked:)
    page = main_page[:page]
    pinned_page = response.fetch(:pinnedPage)
    media_ids = main_page[:media].map { |media| MisskeyCompat::MiId.encode(media.id) }
    content_file_ids = main_page[:file_ids].map { |file_id| MisskeyCompat::MiId.encode(file_id) }
    expect(pinned_page[:id]).to eq(MisskeyCompat::MiId.encode(page.id))
    expect(pinned_page[:attachedFiles].pluck(:id)).to eq(media_ids)
    expect(pinned_page[:content].pluck(:fileId)).to eq(content_file_ids)
    expect(pinned_page[:isLiked]).to eq(liked)
  end
end
