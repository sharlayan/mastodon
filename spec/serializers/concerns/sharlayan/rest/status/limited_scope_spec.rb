# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::REST::Status::LimitedScope do
  subject { serialized_record_json(status, REST::StatusSerializer, options: { scope: current_user, scope_name: :current_user }) }

  let(:owner) { Fabricate(:user) }
  let(:circle) { Circle.create!(account: owner.account, title: 'Friends') }
  let(:status) { Fabricate(:status, account: owner.account, visibility: :limited, limited_scope: :circle).tap { |record| circle.statuses << record } }

  context 'when the author views a circle status' do
    let(:current_user) { owner }

    it 'includes the circle it was published to' do
      expect(subject).to include('limited_scope' => 'circle', 'circle' => { 'id' => circle.id.to_s, 'title' => 'Friends' })
    end

    it 'includes the circle for a circle status without recipients' do
      status.update!(limited_scope: :personal)

      expect(subject).to include('circle' => { 'id' => circle.id.to_s, 'title' => 'Friends' })
    end
  end

  context 'when another account views the circle status' do
    let(:current_user) { Fabricate(:user) }

    it 'does not expose the circle' do
      expect(subject).to include('limited_scope' => 'circle')
      expect(subject).to_not have_key('circle')
    end
  end

  context 'without a current user' do
    let(:current_user) { nil }

    it 'does not expose the circle' do
      expect(subject).to_not have_key('circle')
    end
  end
end
