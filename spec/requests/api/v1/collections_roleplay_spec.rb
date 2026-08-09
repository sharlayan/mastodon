# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Collections in roleplay mode' do
  include_context 'with API authentication', oauth_scopes: 'read:collections write:collections'

  around do |example|
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') { example.run }
  end

  let(:collection) { Fabricate(:collection, account: user.account) }
  let(:collection_item) { Fabricate(:collection_item, collection:) }

  it 'hides collection lists and details' do
    get "/api/v1/accounts/#{user.account_id}/collections", headers: headers

    expect(response).to have_http_status(404)

    get "/api/v1/accounts/#{user.account_id}/in_collections", headers: headers

    expect(response).to have_http_status(404)

    get "/api/v1/collections/#{collection.id}", headers: headers

    expect(response).to have_http_status(404)

    get "/collections/#{collection.id}"

    expect(response).to have_http_status(404)

    get "/redirect/collections/#{Fabricate(:remote_collection).id}"

    expect(response).to have_http_status(404)

    get "/ap/users/#{user.account_id}/collection_items/#{collection_item.id}"

    expect(response).to have_http_status(404)

    get "/ap/users/#{user.account_id}/featured_collections"

    expect(response).to have_http_status(404)
  end

  it 'prevents collection and collection item writes' do
    expect do
      post '/api/v1/collections', headers: headers, params: { name: 'Hidden collection' }
    end.to_not change(Collection, :count)

    expect(response).to have_http_status(404)

    expect do
      post "/api/v1/collections/#{collection.id}/items", headers: headers, params: { account_id: Fabricate(:account).id }
    end.to_not change(CollectionItem, :count)

    expect(response).to have_http_status(404)
  end
end
