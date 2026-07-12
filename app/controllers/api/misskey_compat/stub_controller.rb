# frozen_string_literal: true

class Api::MisskeyCompat::StubController < Api::MisskeyCompat::BaseController
  def empty
    render json: []
  end

  def noop
    render json: {}
  end

  def no_content
    head 204
  end

  def invite_limit
    render json: { remaining: nil }
  end
end
