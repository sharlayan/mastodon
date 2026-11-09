# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AvatarDecorationDomainBlockPolicy do
  subject { described_class }

  let(:admin) { Fabricate(:admin_user).account }
  let(:john)  { Fabricate(:account) }

  permissions :index?, :create?, :destroy? do
    it 'permits staff and denies other accounts' do
      expect(subject).to permit(admin, AvatarDecorationDomainBlock)
      expect(subject).to_not permit(john, AvatarDecorationDomainBlock)
    end
  end
end
