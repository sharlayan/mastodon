# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AvatarDecorationDomainBlockPolicy do
  subject { described_class }

  let(:admin) { Fabricate(:admin_user).account }
  let(:john)  { Fabricate(:account) }

  permissions :index?, :create?, :destroy? do
    context 'when staff' do
      it 'permits' do
        expect(subject).to permit(admin, AvatarDecorationDomainBlock)
      end
    end

    context 'when not staff' do
      it 'denies' do
        expect(subject).to_not permit(john, AvatarDecorationDomainBlock)
      end
    end
  end
end
