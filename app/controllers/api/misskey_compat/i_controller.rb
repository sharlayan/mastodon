# frozen_string_literal: true

class Api::MisskeyCompat::IController < Api::MisskeyCompat::BaseController
  before_action :require_user!

  def show
    render json: MisskeyCompat::UserSerializer.serialize(current_account, detailed: true)
  end
end
