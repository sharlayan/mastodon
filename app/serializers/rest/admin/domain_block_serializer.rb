# frozen_string_literal: true

class REST::Admin::DomainBlockSerializer < ActiveModel::Serializer
  attributes :id, :domain, :digest, :created_at, :severity,
             :reject_media, :reject_reports,
             :reject_favourite, :reject_relay, :block_trends, :hidden,
             :private_comment, :public_comment, :obfuscate

  def id
    object.id.to_s
  end

  def digest
    object.domain_digest
  end
end
