# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::Account::Interactions do
  let(:account) { Fabricate(:account) }

  describe '#unmute_domain!' do
    it 'removes a muted domain and does not raise for an invalid domain name' do
      account.mute_domain!('example.com')

      expect { account.unmute_domain!('example.com') }.to change { account.domain_mutes.count }.from(1).to(0)
      expect(account.unmute_domain!('example com')).to be_nil
    end
  end
end
