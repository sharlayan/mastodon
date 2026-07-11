# frozen_string_literal: true

module MisskeyCompat
  class ScratchpadController < ApplicationController
    layout 'auth'

    skip_before_action :require_functional!

    before_action :require_misskey_compat_enabled!
    before_action :authenticate_user!

    def show; end

    def run
      @code = params[:code].to_s
      parsed = parse_sw_register(@code)

      return render_run_error(:unsupported) if parsed.nil?

      return render_run_error(:wrong_account, expected: parsed[:username], current: current_account.username) if parsed[:username].present? && !parsed[:username].casecmp?(current_account.username)

      access_token_id = current_session&.access_token_id
      return render_run_error(:no_session) if access_token_id.nil?

      subscription, already = MisskeyCompat::SwRegistration.register(
        user: current_user,
        access_token_id: access_token_id,
        endpoint: parsed[:endpoint],
        auth: parsed[:auth],
        publickey: parsed[:publickey]
      )

      @result = MisskeyCompat::SwRegistration.response_for(subscription, already, current_account).to_json
      render :show
    rescue ActiveRecord::RecordInvalid => e
      @error = e.message
      render :show
    end

    private

    def require_misskey_compat_enabled!
      not_found unless Setting.misskey_compat_enabled
    end

    def render_run_error(key, **)
      @error = t("misskey_compat.scratchpad.#{key}", **)
      render :show
    end

    def parse_sw_register(code)
      return nil unless code.match?(%r{Mk:api\(\s*['"]sw/register['"]})

      endpoint = extract(code, 'endpoint')
      auth = extract(code, 'auth')
      publickey = extract(code, 'publickey')
      return nil if endpoint.blank? || auth.blank? || publickey.blank?

      {
        endpoint: endpoint,
        auth: auth,
        publickey: publickey,
        username: code[/USER_USERNAME\s*!=\s*['"]([^'"]*)['"]/, 1],
      }
    end

    def extract(code, key)
      code[/#{key}:\s*['"]([^'"]*)['"]/, 1]
    end
  end
end
