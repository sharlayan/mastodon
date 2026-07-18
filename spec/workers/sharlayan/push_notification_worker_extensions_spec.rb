# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::PushNotificationWorkerExtensions do
  subject(:worker) { Web::PushNotificationWorker.new }

  let(:subscription) { Fabricate.build(:web_push_subscription, endpoint:) }
  let(:response) { instance_double(HTTP::Response, code:) }

  before { worker.instance_variable_set(:@subscription, subscription) }

  context 'with an ignored endpoint domain' do
    let(:endpoint) { 'https://ntfy.sh/push/subscription' }
    let(:code) { 500 }

    it 'treats the response as successful' do
      expect(worker.__send__(:sharlayan_success_response?, response)).to be true
    end
  end

  context 'with an insufficient storage response' do
    let(:endpoint) { 'https://push.example/subscription' }
    let(:code) { 507 }

    it 'treats the response as successful' do
      expect(worker.__send__(:sharlayan_success_response?, response)).to be true
    end
  end
end
