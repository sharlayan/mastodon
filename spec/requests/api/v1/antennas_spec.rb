# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Antennas' do
  include_context 'with API authentication', oauth_scopes: 'read:lists write:lists'

  describe 'GET /api/v1/antennas' do
    subject { get '/api/v1/antennas', headers: headers }

    let!(:antenna) { Fabricate(:antenna, account: user.account, title: 'mine') }

    before { Fabricate(:antenna) } # someone else's

    it 'returns only the current user antennas' do
      subject

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to eq([antenna.id.to_s])
    end
  end

  describe 'POST /api/v1/antennas' do
    subject { post '/api/v1/antennas', headers: headers, params: { title: 'new antenna', keywords: %w(commission) } }

    it 'creates an antenna while locking the account to validate the per-account limit' do
      queries = []
      callback = lambda do |_name, _started, _finished, _unique_id, payload|
        queries << payload[:sql] if payload[:name] != 'SCHEMA' && !payload[:cached]
      end

      expect { ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { subject } }.to change(Antenna, :count).by(1)

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:title]).to eq('new antenna')
      expect(response.parsed_body[:keywords]).to eq(%w(commission))
      expect(queries.any? { |sql| sql.include?('FROM "accounts"') && sql.include?('FOR UPDATE') }).to be(true)
    end
  end

  describe 'PUT /api/v1/antennas/:id' do
    subject { put "/api/v1/antennas/#{antenna.id}", headers: headers, params: { available: false } }

    let(:antenna) { Fabricate(:antenna, account: user.account) }

    it 'updates the antenna' do
      subject

      expect(response).to have_http_status(200)
      expect(antenna.reload.available).to be(false)
    end
  end

  describe 'DELETE /api/v1/antennas/:id' do
    subject { delete "/api/v1/antennas/#{antenna.id}", headers: headers }

    let!(:antenna) { Fabricate(:antenna, account: user.account) }

    it 'deletes the antenna' do
      expect { subject }.to change(Antenna, :count).by(-1)
      expect(response).to have_http_status(200)
    end
  end

  describe 'DELETE /api/v1/antennas/:antenna_id/statuses/:id' do
    subject { delete "/api/v1/antennas/#{antenna.id}/statuses/#{status.id}", headers: headers }

    let(:antenna) { Fabricate(:antenna, account: user.account) }
    let(:status) { Fabricate(:status) }

    before do
      FeedManager.instance.push_to_antenna(antenna, status)
    end

    it 'excludes the status and removes it from the antenna feed' do
      subject
      expect(response).to have_http_status(200)
      expect(AntennaFeed.new(antenna).get(10)).to_not include(status)
    end

    it 'does not allow excluding a status that is not in the antenna feed' do
      FeedManager.instance.unpush_from_antenna(antenna, status)

      subject
      expect(response).to have_http_status(404)
    end

    context 'when the feed item is a boost' do
      let(:original_status) { Fabricate(:status) }
      let(:status) { Fabricate(:status, reblog: original_status) }

      it 'removes current representations of the original without permanently blocking it' do
        subject

        expect(AntennaFeed.new(antenna).get(10)).to be_empty
        expect(FeedManager.instance.filter(:antenna, status, antenna)).to be_nil
      end
    end
  end

  describe 'GET /api/v1/timelines/antenna/:id' do
    let(:antenna) { Fabricate(:antenna, account: user.account) }

    it 'filters stale inaccessible entries while preserving pagination through the scanned rows' do
      author = Fabricate(:account)
      public_status = Fabricate(:status, account: author, id: Mastodon::Snowflake.id_at(1.minute.ago))
      private_status = Fabricate(:status, account: author, visibility: :private)
      [public_status, private_status].each { |status| FeedManager.instance.push_to_antenna(antenna, status) }

      get "/api/v1/timelines/antenna/#{antenna.id}", headers: headers, params: { limit: 1 }

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to be_empty
      expect(response.headers['Link']).to include('rel="next"')

      get URI.parse(response.headers['Link'][/<([^>]+)>; rel="next"/, 1]).request_uri, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to eq([public_status.id.to_s])
    end

    it 'checks visibility of a page with a fixed number of relationship queries' do
      relationship_queries = lambda do
        count = 0
        counter = ->(*, payload) { count += 1 if !payload[:cached] && /FROM "(follows|blocks|mentions)"/.match?(payload[:sql]) }
        ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { get "/api/v1/timelines/antenna/#{antenna.id}", headers: headers }
        count
      end
      push_statuses = lambda do |count|
        Fabricate.times(count, :account).product(%i(public private limited)).each do |author, visibility|
          user.account.follow!(author)
          FeedManager.instance.push_to_antenna(antenna, Fabricate(:status, account: author, visibility:))
        end
      end

      push_statuses.call(1)
      single_author = relationship_queries.call
      push_statuses.call(3)

      expect(relationship_queries.call).to be <= single_author
      expect(response.parsed_body.size).to eq(8)
    end
  end

  %w(accounts domains tags).each do |condition|
    describe "POST /api/v1/antennas/:id/#{condition} locking" do
      let(:antenna) { Fabricate(:antenna, account: user.account) }
      let(:queries) { [] }

      it 'locks the antenna before counting and adding conditions' do
        params = case condition
                 when 'accounts'
                   { account_ids: [Fabricate(:account).id.to_s] }
                 when 'domains'
                   { domains: ['example.com'] }
                 else
                   { tags: ['example'] }
                 end
        antenna
        callback = lambda do |_name, _started, _finished, _unique_id, payload|
          queries << payload[:sql] if payload[:name] != 'SCHEMA' && !payload[:cached]
        end

        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
          post "/api/v1/antennas/#{antenna.id}/#{condition}", headers: headers, params: params
        end

        expect(response).to have_http_status(200)
        lock_index = queries.index { |sql| sql.include?('FROM "antennas"') && sql.include?('FOR UPDATE') }
        count_index = queries.index { |sql| sql.include?("\"antenna_#{condition}\"") && sql.start_with?('SELECT') }
        expect(lock_index).to be_present
        expect(count_index).to be > lock_index
      end
    end
  end

  describe 'POST /api/v1/antennas/:id/domains' do
    let(:antenna) { Fabricate(:antenna, account: user.account) }

    it 'adds include domain conditions in the same form as account domains' do
      post "/api/v1/antennas/#{antenna.id}/domains", headers: headers, params: { domains: ['Example.COM', 'xn--3e0b707e.example', '한국.example'] }

      expect(response).to have_http_status(200)
      expect(antenna.antenna_domains.includes_only.pluck(:name)).to contain_exactly('example.com', 'xn--3e0b707e.example')
    end

    it 'normalizes excluded domains' do
      post "/api/v1/antennas/#{antenna.id}/exclude_domains", headers: headers, params: { domains: ['Example.COM'] }

      expect(antenna.reload.exclude_domains).to eq ['example.com']
    end
  end

  describe 'POST /api/v1/antennas/:id/accounts' do
    subject { post "/api/v1/antennas/#{antenna.id}/accounts", headers: headers, params: { account_ids: [extra_account.id.to_s] } }

    let(:antenna) { Fabricate(:antenna, account: user.account) }
    let(:existing_account) { Fabricate(:account) }
    let(:extra_account) { Fabricate(:account) }

    before do
      stub_const 'Antenna::ACCOUNTS_PER_ANTENNA_LIMIT', 1
      antenna.antenna_accounts.create!(account: existing_account)
    end

    it 'rejects limit overflow without creating extra conditions' do
      expect { subject }.to_not(change { antenna.antenna_accounts.includes_only.count })
      expect(response).to have_http_status(422)
    end
  end

  describe 'POST /api/v1/antennas/:id/domains over limit' do
    subject { post "/api/v1/antennas/#{antenna.id}/domains", headers: headers, params: { domains: ['extra.example'] } }

    let(:antenna) { Fabricate(:antenna, account: user.account) }

    before do
      stub_const 'Antenna::DOMAINS_PER_ANTENNA_LIMIT', 1
      antenna.antenna_domains.create!(name: 'existing.example')
    end

    it 'rejects limit overflow without creating extra conditions' do
      expect { subject }.to_not(change { antenna.antenna_domains.includes_only.count })
      expect(response).to have_http_status(422)
    end
  end

  describe 'POST /api/v1/antennas/:id/tags' do
    subject { post "/api/v1/antennas/#{antenna.id}/tags", headers: headers, params: { tags: ['extra'] } }

    let(:antenna) { Fabricate(:antenna, account: user.account) }
    let(:existing_tag) { Fabricate(:tag, name: 'existing') }

    before do
      stub_const 'Antenna::TAGS_PER_ANTENNA_LIMIT', 1
      antenna.antenna_tags.create!(tag: existing_tag)
    end

    it 'rejects limit overflow without creating extra conditions' do
      expect { subject }.to_not(change { antenna.antenna_tags.includes_only.count })
      expect(response).to have_http_status(422)
    end
  end
end
