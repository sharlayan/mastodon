# frozen_string_literal: true

module Sharlayan::REST::Account::Pages
  extend ActiveSupport::Concern

  included do
    attribute :pages_view, if: :local?
    attribute :pages_blog_list_position, if: :local?
  end

  def pages_view
    object.user&.settings&.[]('web.pages_view') || 'list'
  end

  def pages_blog_list_position
    object.user&.settings&.[]('web.pages_blog_list_position') || 'left'
  end
end
