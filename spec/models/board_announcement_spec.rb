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
end
