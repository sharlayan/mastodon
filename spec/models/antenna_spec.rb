# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Antenna do
  describe 'Validations' do
    subject { Fabricate.build :antenna }

    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_length_of(:title).is_at_most(described_class::TITLE_LENGTH_LIMIT) }

    context 'when account has hit the antenna limit' do
      let(:account) { Fabricate :account }

      before do
        stub_const 'Antenna::ANTENNAS_PER_ACCOUNT_LIMIT', 1
        Fabricate(:antenna, account: account)
      end

      it 'is invalid on create but allows editing existing antennas' do
        expect(Fabricate.build(:antenna, account: account)).to_not be_valid
        expect { account.antennas.first.update!(title: 'Renamed') }.to_not raise_error
      end
    end

    it 'rejects keywords shorter than the minimum length' do
      antenna = Fabricate.build(:antenna, keywords: ['a'], any_keywords: false)
      expect(antenna).to_not be_valid
    end

    it 'rejects oversized include and exclude keyword lists' do
      too_many = Array.new(described_class::KEYWORDS_PER_ANTENNA_LIMIT + 1, 'keyword')

      expect(Fabricate.build(:antenna, keywords: too_many, any_keywords: false)).to_not be_valid
      expect(Fabricate.build(:antenna, exclude_keywords: too_many)).to_not be_valid
    end

    it 'rejects oversized include and exclude keywords' do
      too_long = 'a' * (described_class::MAX_KEYWORD_LENGTH + 1)

      expect(Fabricate.build(:antenna, keywords: [too_long], any_keywords: false)).to_not be_valid
      expect(Fabricate.build(:antenna, exclude_keywords: [too_long])).to_not be_valid
    end
  end

  describe '#matches? and .matching' do
    let(:account) { Fabricate(:account) }
    let(:author)  { Fabricate(:account, domain: nil, username: 'author') }

    def status_with(text:, tags: [])
      status = Fabricate(:status, account: author, text: text, visibility: :public)
      status.tags = tags
      status
    end

    it 'matches a keyword condition with substring semantics (AND across types, OR within)' do
      antenna = Fabricate(:antenna, account: account, any_keywords: false, keywords: %w(commission art))
      expect(antenna.matches?(status_with(text: 'open for commission'))).to be true
      expect(antenna.matches?(status_with(text: 'nothing here'))).to be false
    end

    it 'applies exclude keywords' do
      antenna = Fabricate(:antenna, account: account, any_keywords: false, keywords: %w(art), exclude_keywords: %w(spoiler))
      expect(antenna.matches?(status_with(text: 'my art is great'))).to be true
      expect(antenna.matches?(status_with(text: 'art spoiler ahead'))).to be false
    end

    it 'applies excluded domains without recursive lookup' do
      remote_author = Fabricate(:account, domain: 'remote.example')
      status = Fabricate(:status, account: remote_author, text: 'hello', visibility: :public)
      antenna = Fabricate(:antenna, account: account, any_keywords: false, keywords: %w(hello), exclude_domains: %w(remote.example))

      expect(antenna.matches?(status)).to be false
    end

    it 'requires the account include condition when any_accounts is false' do
      other = Fabricate(:account)
      antenna = Fabricate(:antenna, account: account, any_accounts: false)
      antenna.antenna_accounts.create!(account: other)
      expect(antenna.matches?(status_with(text: 'hi'))).to be false
      antenna.antenna_accounts.create!(account: author)
      expect(antenna.reload.matches?(status_with(text: 'hi'))).to be true
    end

    it 'narrows candidates via .matching' do
      Fabricate(:user, account: account, current_sign_in_at: Time.now.utc)
      antenna = Fabricate(:antenna, account: account, any_keywords: false, keywords: %w(hello))
      status = status_with(text: 'hello world')
      expect(described_class.matching(status)).to include(antenna)
    end

    it 'does not operate when no conditions are configured' do
      Fabricate(:user, account: account, current_sign_in_at: Time.now.utc)
      antenna = Fabricate(:antenna, account: account)
      status = status_with(text: 'anything at all')
      expect(antenna.configured?).to be false
      expect(antenna.matches?(status)).to be false
      expect(described_class.matching(status)).to_not include(antenna)
    end
  end
end
