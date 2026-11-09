# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AvatarDecorationPolicy do
  subject { described_class }

  let(:admin) { Fabricate(:admin_user).account }
  let(:john)  { Fabricate(:account) }

  permissions :index?, :create?, :update?, :destroy? do
    it 'permits staff and denies other accounts' do
      expect(subject).to permit(admin, AvatarDecoration)
      expect(subject).to_not permit(john, AvatarDecoration)
    end
  end
end
