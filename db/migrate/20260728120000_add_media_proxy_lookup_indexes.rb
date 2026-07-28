# frozen_string_literal: true

class AddMediaProxyLookupIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :media_attachments, :remote_url, using: :hash, where: "remote_url <> ''", name: :index_media_attachments_on_remote_url_hash, algorithm: :concurrently, if_not_exists: true
    add_index :media_attachments, :thumbnail_remote_url, using: :hash, where: 'thumbnail_remote_url IS NOT NULL', name: :index_media_attachments_on_thumbnail_remote_url_hash, algorithm: :concurrently, if_not_exists: true
    add_index :custom_emojis, :image_remote_url, using: :hash, where: 'image_remote_url IS NOT NULL', name: :index_custom_emojis_on_image_remote_url_hash, algorithm: :concurrently, if_not_exists: true
    add_index :instance_metadata, :favicon_url, using: :hash, where: 'favicon_url IS NOT NULL', name: :index_instance_metadata_on_favicon_url_hash, algorithm: :concurrently, if_not_exists: true
  end
end
