# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BoardAnnouncement do
  describe '.for_account' do
    subject(:visible_announcements) { described_class.for_account(account) }

    let(:account) { Fabricate(:account, created_at: 2.days.ago) }
    let!(:global_announcement) { described_class.create!(title: 'Global', text: 'Body', published: true, published_at: 3.days.ago) }
    let!(:old_existing_users_announcement) { described_class.create!(title: 'Old existing users', text: 'Body', published: true, published_at: 3.days.ago, for_existing_users: true) }
    let!(:new_existing_users_announcement) { described_class.create!(title: 'New existing users', text: 'Body', published: true, published_at: 1.day.ago, for_existing_users: true) }

    it 'includes global announcements and existing-user announcements published after account creation' do
      expect(visible_announcements).to include(global_announcement, new_existing_users_announcement)
      expect(visible_announcements).to_not include(old_existing_users_announcement)
    end
  end

  describe 'sort_priority validation' do
    it 'rejects blank or out-of-range priorities and accepts negative and positive priorities within range' do
      blank = described_class.new(title: 'Title', text: 'Body', sort_priority: '')
      out_of_range = described_class.new(title: 'Title', text: 'Body', sort_priority: '99999999999')

      expect(blank).to_not be_valid
      expect(blank.errors[:sort_priority]).to be_present
      expect(out_of_range).to_not be_valid
      expect(out_of_range.errors[:sort_priority]).to be_present
      expect(described_class.new(title: 'Title', text: 'Body', sort_priority: '-5')).to be_valid
      expect(described_class.new(title: 'Title', text: 'Body', sort_priority: '2147483647')).to be_valid
    end
  end
end
