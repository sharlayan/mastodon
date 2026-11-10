# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::PushNotificationWorkerExtensions do
  def success_response?(endpoint, code)
    worker = Web::PushNotificationWorker.new
    worker.instance_variable_set(:@subscription, Fabricate.build(:web_push_subscription, endpoint:))
    worker.__send__(:sharlayan_success_response?, instance_double(HTTP::Response, code:))
  end

  it 'treats responses from ignored endpoint domains and insufficient storage responses as successful' do
    expect(success_response?('https://ntfy.sh/push/subscription', 500)).to be true
    expect(success_response?('https://push.example/subscription', 507)).to be true
  end
end
