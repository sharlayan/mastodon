# frozen_string_literal: true

class ValidatePageSeriesForeignKeys < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :page_series, :pages
    validate_foreign_key :pages, :page_series
  end
end
