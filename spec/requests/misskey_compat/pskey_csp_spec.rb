# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Pskey Content-Security-Policy relaxation' do
  def script_src
    response
      .headers['Content-Security-Policy']
      .split(';')
      .map(&:strip)
      .find { |directive| directive.start_with?('script-src ') }
  end

  context 'when misskey_compat is enabled' do
    before { Setting.misskey_compat_enabled = true }

    it "adds 'unsafe-eval' to script-src for Pskey WebView requests" do
      get '/', headers: { 'HTTP_USER_AGENT' => 'Mozilla/5.0 Pskey mobile' }

      expect(script_src).to include("'unsafe-eval'")
    end

    it "does not add 'unsafe-eval' for regular browsers" do
      get '/', headers: { 'HTTP_USER_AGENT' => 'Mozilla/5.0 Chrome' }

      expect(script_src).to_not include("'unsafe-eval'")
    end
  end

  context 'when misskey_compat is disabled' do
    before { Setting.misskey_compat_enabled = false }

    it "does not add 'unsafe-eval' even for Pskey requests" do
      get '/', headers: { 'HTTP_USER_AGENT' => 'Mozilla/5.0 Pskey mobile' }

      expect(script_src).to_not include("'unsafe-eval'")
    end
  end
end
