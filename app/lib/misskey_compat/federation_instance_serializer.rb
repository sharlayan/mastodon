# frozen_string_literal: true

class MisskeyCompat::FederationInstanceSerializer
  include RoutingHelper

  Context = Struct.new(:suspended, :silenced, :media_silenced, :unavailable, keyword_init: true)

  def self.build_context(domains, domain_blocks_visible: true)
    domains = domains.compact.uniq
    InstanceMetadata.preload_domains(domains)
    blocks = domain_blocks_visible ? DomainBlock.where(domain: domains) : DomainBlock.none

    Context.new(
      suspended: blocks.where(severity: :suspend).pluck(:domain).to_set,
      silenced: blocks.where(severity: :silence).pluck(:domain).to_set,
      media_silenced: blocks.where(reject_media: true).pluck(:domain).to_set,
      unavailable: UnavailableDomain.where(domain: domains).pluck(:domain).to_set
    )
  end

  def self.serialize(stat, context:)
    new(context).serialize(stat)
  end

  def initialize(context)
    @context = context
  end

  def serialize(stat)
    domain = stat.domain
    metadata = InstanceMetadata.cached_by_domain(domain)
    suspended = @context.suspended.include?(domain)

    {
      id: MisskeyCompat::MiId.encode(stat.id),
      firstRetrievedAt: (stat.first_retrieved_at || stat.created_at).iso8601,
      host: domain,
      usersCount: stat.users_count,
      notesCount: stat.notes_count,
      followingCount: stat.following_count,
      followersCount: stat.followers_count,
      isNotResponding: @context.unavailable.include?(domain),
      isSuspended: suspended,
      suspensionState: suspended ? 'manuallySuspended' : 'none',
      isBlocked: suspended,
      softwareName: metadata&.software,
      softwareVersion: metadata&.version,
      openRegistrations: nil,
      name: metadata&.instance_name_with_fallback || domain,
      description: nil,
      maintainerName: nil,
      maintainerEmail: nil,
      isSilenced: @context.silenced.include?(domain),
      isMediaSilenced: @context.media_silenced.include?(domain),
      iconUrl: favicon_url(metadata),
      faviconUrl: favicon_url(metadata),
      themeColor: metadata&.theme_color_with_fallback,
      infoUpdatedAt: metadata&.metadata_updated_at&.iso8601,
      latestRequestReceivedAt: nil,
      moderationNote: nil,
    }
  end

  private

  def favicon_url(metadata)
    url = metadata&.favicon_url_with_fallback
    return if url.blank?
    return url if url.start_with?('http://', 'https://')

    full_asset_url(url)
  end
end
