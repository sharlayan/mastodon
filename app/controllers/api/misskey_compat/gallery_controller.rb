# frozen_string_literal: true

class Api::MisskeyCompat::GalleryController < Api::MisskeyCompat::BaseController
  def empty
    render json: []
  end

  def noop
    render json: {}
  end
end
