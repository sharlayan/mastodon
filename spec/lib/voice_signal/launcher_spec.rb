# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib', 'voice_signal', 'launcher').to_s

RSpec.describe VoiceSignal::Launcher do
  let(:root) { Dir.mktmpdir }
  let(:bin) { File.join(root, 'path-bin').tap { |path| FileUtils.mkdir_p(path) } }
  let(:publish) { File.join(root, 'voice_signal', 'publish').tap { |path| FileUtils.mkdir_p(path) } }
  let(:quiet) { ->(_message) {} }

  after { FileUtils.rm_rf(root) }

  def executable(path, body = "#!/bin/sh\nexit 0\n")
    File.write(path, body)
    File.chmod(0o755, path)
    path
  end

  def launcher(mode, **environment)
    described_class.new(root:, environment: { 'PATH' => bin }.merge(environment.transform_keys(&:to_s)), mode:, log: quiet)
  end

  def wait_until(timeout = 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    sleep 0.05 until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    yield
  end

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  it 'stays off unless enabled and reads the Mastodon environment files under the process environment' do
    File.write(File.join(root, '.env.production'), "VOICE_SIGNAL_SPAWN=binary\nLOCAL_DOMAIN=file.example\nSECRET_KEY_BASE=from-file\n")

    expect(described_class.from_environment(root:, env: { 'RAILS_ENV' => 'production', 'VOICE_SIGNAL_SPAWN' => 'off' }, log: quiet)).to be_nil
    expect(described_class.from_environment(root:, env: { 'RAILS_ENV' => 'development' }, log: quiet)).to be_nil

    enabled = described_class.from_environment(root:, env: { 'RAILS_ENV' => 'production', 'LOCAL_DOMAIN' => 'env.example' }, log: quiet)
    expect(enabled.mode).to eq 'binary'
    expect(enabled.environment).to include(
      'LOCAL_DOMAIN' => 'env.example', 'SECRET_KEY_BASE' => 'from-file', 'VOICE_SIGNAL_BIND' => '127.0.0.1', 'VOICE_SIGNAL_EXIT_ON_STDIN_EOF' => '1'
    )
    expect { described_class.from_environment(root:, env: { 'VOICE_SIGNAL_SPAWN' => 'sometimes' }, log: quiet) }.to raise_error(described_class::ConfigurationError)
  end

  it 'prefers a local build and otherwise runs the published image without exposing secrets in its arguments' do
    docker = executable(File.join(bin, 'docker'))
    socket = File.join(root, 'postgresql').tap { |path| FileUtils.mkdir_p(path) }

    command = launcher('auto', SECRET_KEY_BASE: 'top-secret', DB_HOST: socket, DB_PASS: 'db-secret', VOICE_SIGNAL_PORT: '4300').command
    expect(command).to eq [
      docker, 'run', '--rm', '--interactive', '--name', 'mastodon-voice-signal-4300', '--pull=missing', '--network', 'host',
      '--user', "#{Process.uid}:#{Process.gid}", '--volume', "#{socket}:#{socket}",
      '--env', 'SECRET_KEY_BASE', '--env', 'DB_HOST', '--env', 'DB_PASS', '--env', 'VOICE_SIGNAL_BIND', '--env', 'VOICE_SIGNAL_PORT', '--env', 'VOICE_SIGNAL_EXIT_ON_STDIN_EOF',
      described_class::DEFAULT_IMAGE
    ]
    expect(command.join(' ')).to_not include('top-secret', 'db-secret')
    expect(launcher('docker', VOICE_SIGNAL_IMAGE: 'example/voice:1', VOICE_SIGNAL_IMAGE_PULL: 'always').command).to include('--pull=always', 'example/voice:1')
    expect { launcher('docker', VOICE_SIGNAL_IMAGE_PULL: 'sometimes').command }.to raise_error(described_class::ConfigurationError)

    dll = File.join(publish, 'VoiceSignal.dll').tap { |path| File.write(path, '') }
    expect(launcher('auto').command).to eq [docker, *launcher('docker').command.drop(1)]
    dotnet = executable(File.join(bin, 'dotnet'))
    expect(launcher('auto').command).to eq [dotnet, dll]

    native = executable(File.join(publish, 'VoiceSignal'))
    expect(launcher('auto').command).to eq [native]
    expect(launcher('binary', VOICE_SIGNAL_BINARY: dll).command).to eq [dotnet, dll]
  end

  it 'runs as a dedicated service without the parent watch' do
    executable(File.join(bin, 'docker'))

    service = described_class.new(root:, environment: { 'PATH' => bin, 'VOICE_SIGNAL_EXIT_ON_STDIN_EOF' => '1' }, mode: 'docker', supervised: false, log: quiet)
    expect(service.environment['VOICE_SIGNAL_EXIT_ON_STDIN_EOF']).to be_nil
    expect(service.command).to_not include('--interactive', 'VOICE_SIGNAL_EXIT_ON_STDIN_EOF')
    expect(launcher('docker').command).to include('--interactive', 'VOICE_SIGNAL_EXIT_ON_STDIN_EOF')

    expect(described_class.spawn_mode('VOICE_SIGNAL_SPAWN' => ' Auto ')).to eq 'auto'
    expect(described_class.spawn_mode('VOICE_SIGNAL_SPAWN' => 'off')).to be_nil
  end

  it 'refuses modes whose runtime is missing' do
    expect { launcher('binary').command }.to raise_error(described_class::ConfigurationError)
    expect { launcher('docker').command }.to raise_error(described_class::ConfigurationError)
    expect(launcher('auto').start).to be_nil
  end

  it 'restarts the process when it exits and stops it with the server' do
    pids = File.join(root, 'pids')
    cat = %w(/usr/bin/cat /bin/cat).find { |path| File.executable?(path) }
    executable(File.join(publish, 'VoiceSignal'), "#!/bin/sh\necho $$ >> #{pids}\nexec #{cat} > /dev/null\n")
    supervisor = launcher('binary').start

    expect(wait_until { File.exist?(pids) && File.readlines(pids).size == 1 }).to be true
    first = File.readlines(pids).first.to_i
    Process.kill('TERM', first)

    expect(wait_until { File.readlines(pids).size == 2 }).to be true
    second = File.readlines(pids).last.to_i
    expect(wait_until { supervisor.pid == second }).to be true

    supervisor.stop
    expect(supervisor.running?).to be false
    expect(wait_until { !alive?(second) }).to be true
  end
end
