# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat notes/drafts endpoints' do
  describe 'endpoint advertisement' do
    it 'are not advertised so Aria hides the server-draft UI' do
      names = Api::MisskeyCompat::MetaController.compat_endpoint_names

      expect(names).to_not include(a_string_matching(%r{notes/drafts}))
    end
  end
end
