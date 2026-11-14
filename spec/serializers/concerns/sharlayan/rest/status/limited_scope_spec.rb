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

    it 'hides that the status was published to a circle' do
      expect(subject).to include('visibility' => 'private', 'limited_scope' => 'none')
      expect(subject).to_not have_key('circle')

      status.update!(limited_scope: :personal)
      expect(serialized_record_json(status.reload, REST::StatusSerializer, options: { scope: current_user, scope_name: :current_user })).to include('limited_scope' => 'none')
    end

    it 'does not include the source audience when another account requests the source' do
      source = ->(record) { serialized_record_json(record, REST::StatusSerializer, options: { scope: current_user, scope_name: :current_user, source_requested: true }) }
      expect(source.call(status)).to_not include('circle_id')

      reply = Fabricate(:status, account: owner.account, visibility: :limited, limited_scope: :reply, thread: status)
      reply.mentions.create!(account: Fabricate(:account), silent: true)
      expect(source.call(reply)).to_not include('limited_reply_account_ids')
    end

    it 'keeps the reply audience scope' do
      status.update!(limited_scope: :reply)

      expect(subject).to include('limited_scope' => 'reply')
    end
  end

  context 'without a current user' do
    let(:current_user) { nil }

    it 'hides that the status was published to a circle' do
      expect(subject).to include('limited_scope' => 'none')
      expect(subject).to_not have_key('circle')
    end
  end
end
