# frozen_string_literal: true

class Api::MisskeyCompat::PagesController < Api::MisskeyCompat::BaseController
  def empty
    render json: []
  end

  def unsupported
    render_error('Pages are not supported on this server', 'UNSUPPORTED_ENDPOINT', 501, kind: 'server')
  end
end
