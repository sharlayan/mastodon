# frozen_string_literal: true

class UsePagesSequenceForPageSeriesIds < ActiveRecord::Migration[8.0]
  def up
    change_column_default :page_series, :id, from: -> { "timestamp_id('page_series')" }, to: -> { "timestamp_id('pages')" }
  end

  def down
    change_column_default :page_series, :id, from: -> { "timestamp_id('pages')" }, to: -> { "timestamp_id('page_series')" }
  end
end
