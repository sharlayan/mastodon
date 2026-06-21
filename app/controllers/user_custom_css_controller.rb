# frozen_string_literal: true

class UserCustomCssController < ActionController::Base # rubocop:disable Rails/ApplicationController
  before_action :authenticate_user!

  def show
    expires_in 1.year, public: false
    css = Setting.allow_user_custom_css ? current_user.custom_css_text.to_s : ''
    render plain: css, content_type: 'text/css'
  end
end
