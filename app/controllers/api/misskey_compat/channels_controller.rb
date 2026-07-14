# frozen_string_literal: true

class Api::MisskeyCompat::ChannelsController < Api::MisskeyCompat::BaseController
  def empty
    render json: []
  end

  def noop
    head 204
  end
end
