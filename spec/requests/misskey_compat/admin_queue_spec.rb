# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/api'

RSpec.describe 'Misskey-compat admin queue' do
  let(:role) { Fabricate(:user_role, permissions: UserRole::FLAGS[:view_devops]) }
  let(:user) { Fabricate(:user, role: role) }
  let(:token) { MisskeyCompat::MiAuth.issue_native_token(user).token }

  def clear_sidekiq
    %w(push ingress default pull scheduler).each { |name| Sidekiq::Queue.new(name).clear }
    [Sidekiq::ScheduledSet, Sidekiq::RetrySet, Sidekiq::DeadSet].each { |set| set.new.clear }
  end

  def push(klass, args, **options)
    Sidekiq.testing!(:disable) { Sidekiq::Client.push({ 'class' => klass, 'queue' => 'push', 'args' => args }.merge(options.transform_keys(&:to_s))) }
  end

  def api(path, **params)
    Sidekiq.testing!(:disable) { post "/api/admin/queue/#{path}", params: { i: token }.merge(params), as: :json }
    response.parsed_body
  end

  before do
    Setting.misskey_compat_enabled = true
    clear_sidekiq
  end

  after do
    clear_sidekiq
    Setting.misskey_compat_enabled = false
  end

  it 'maps Misskey queues to Sidekiq queues and worker classes' do
    push('ActivityPub::DeliveryWorker', ['{}', 1, 'https://remote.example/inbox'])
    scheduled = push('ActivityPub::DeliveryWorker', ['{}', 1, 'https://later.example/inbox'], at: 1.hour.from_now.to_f)
    push('MisskeyCompatWebhookDeliveryWorker', [1, '{}'])

    queues = api('queues').index_by { |queue| queue[:name].to_sym }
    expect(queues[:deliver]).to include(counts: include(waiting: 1, delayed: 1, failed: 0), isPaused: false)
    expect(queues[:userWebhookDeliver][:counts]).to include(waiting: 1)
    expect(queues[:objectStorage][:counts]).to include(waiting: 0)
    expect(api('stats')[:deliver]).to include(waiting: 1, delayed: 1)
    expect(api('queue-stats', queue: 'deliver')).to include(name: 'deliver', qualifiedName: 'queue:push', db: include(:version))

    jobs = api('jobs', queue: 'deliver', state: %w(wait delayed))
    expect(jobs.pluck(:name)).to eq(%w(ActivityPub::DeliveryWorker ActivityPub::DeliveryWorker))
    expect(api('jobs', queue: 'deliver', state: %w(wait delayed), search: 'later.example').pluck(:id)).to eq([scheduled])
    expect(api('deliver-delayed')).to eq([['later.example', 1]])
    expect(api('show-job', queue: 'deliver', jobId: scheduled)).to include(id: scheduled, delay: be_positive)
    expect(api('show-job-logs', queue: 'deliver', jobId: scheduled)).to eq([])
  end

  it 'retries, removes, promotes and clears jobs of the mapped queue only' do
    scheduled = push('ActivityPub::DeliveryWorker', ['{}', 1, 'https://later.example/inbox'], at: 1.hour.from_now.to_f)
    waiting = push('ActivityPub::DeliveryWorker', ['{}', 1, 'https://now.example/inbox'])
    webhook = push('MisskeyCompatWebhookDeliveryWorker', [1, '{}'])

    api('retry-job', queue: 'deliver', jobId: scheduled)
    expect(Sidekiq::Queue.new('push').map(&:jid)).to include(scheduled)

    api('remove-job', queue: 'deliver', jobId: waiting)
    expect(Sidekiq::Queue.new('push').map(&:jid)).to contain_exactly(scheduled, webhook)

    push('ActivityPub::DeliveryWorker', ['{}', 1, 'https://later.example/inbox'], at: 1.hour.from_now.to_f)
    api('promote-jobs', queue: 'deliver')
    expect(Sidekiq::ScheduledSet.new.size).to eq(0)

    api('clear', queue: 'deliver', state: '*')
    expect(Sidekiq::Queue.new('push').map(&:jid)).to eq([webhook])

    api('show-job', queue: 'deliver', jobId: 'missing')
    expect(response).to have_http_status(404)

    api('pause', queue: 'deliver')
    expect(response).to have_http_status(501)
  end

  it 'requires the devops permission' do
    user.update!(role: Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_settings]))
    api('queues')

    expect(response).to have_http_status(403)
  end
end
