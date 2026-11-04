# frozen_string_literal: true

# Most chat specs are not about who may start a chat, so they lift the default of mutual followers only.
RSpec.shared_context 'with an open chat policy' do
  before { allow(UserSettings.definition_for(:chat_policy)).to receive(:default_value).and_return('everyone') }
end
