# frozen_string_literal: true

RSpec.shared_context 'with an open chat policy' do
  before { allow(UserSettings.definition_for(:chat_policy)).to receive(:default_value).and_return('everyone') }
end
