# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib', 'voice_signal', 'build').to_s

RSpec.describe VoiceSignal::Build do
  let(:root) { Dir.mktmpdir }
  let(:bin) { File.join(root, 'path-bin').tap { |path| FileUtils.mkdir_p(path) } }

  after { FileUtils.rm_rf(root) }

  def executable(name)
    File.join(bin, name).tap do |path|
      File.write(path, "#!/bin/sh\n")
      File.chmod(0o755, path)
    end
  end

  def build(cpu: 'x86_64', musl: false)
    described_class.new(root:, environment: { 'PATH' => bin }, cpu:, musl:)
  end

  it 'publishes a self-contained executable with dotnet, or inside the official SDK container without it' do
    publish = ['--configuration', 'Release', '--runtime', 'linux-x64', '--self-contained', '--output', 'voice_signal/publish.new', '-p:PublishSingleFile=true', '-p:DebugType=none']

    docker = executable('docker')
    expect(build.command).to eq [
      docker, 'run', '--rm', '--user', "#{Process.uid}:#{Process.gid}",
      '--env', 'HOME=/tmp', '--env', 'DOTNET_CLI_TELEMETRY_OPTOUT=1', '--env', 'DOTNET_NOLOGO=1',
      '--volume', "#{File.join(root, 'voice_signal')}:/work/voice_signal", '--workdir', '/work',
      described_class::SDK_IMAGE, 'dotnet', 'publish', 'voice_signal/src/VoiceSignal/VoiceSignal.csproj', *publish
    ]

    dotnet = executable('dotnet')
    expect(build.command).to eq [dotnet, 'publish', 'voice_signal/src/VoiceSignal/VoiceSignal.csproj', *publish]
  end

  it 'targets the host architecture and refuses when no build tool is available' do
    expect(build(cpu: 'aarch64').runtime).to eq 'linux-arm64'
    expect(build(cpu: 'x86_64', musl: true).runtime).to eq 'linux-musl-x64'
    expect { build(cpu: 'riscv64').runtime }.to raise_error(described_class::Error)
    expect { build.command }.to raise_error(described_class::Error)
  end

  it 'keeps the previous executable when a build fails and replaces it only after a successful build' do
    publish = File.join(root, 'voice_signal', 'publish').tap { |path| FileUtils.mkdir_p(path) }
    File.write(File.join(publish, 'VoiceSignal'), 'previous')
    dotnet = File.join(bin, 'dotnet')

    File.write(dotnet, "#!/bin/sh\nexit 1\n")
    File.chmod(0o755, dotnet)
    expect { build.run! }.to raise_error(described_class::Error)
    expect(File.read(File.join(publish, 'VoiceSignal'))).to eq 'previous'

    File.write(dotnet, "#!/bin/sh\nmkdir -p voice_signal/publish.new\nprintf new > voice_signal/publish.new/VoiceSignal\nchmod 755 voice_signal/publish.new/VoiceSignal\ntouch voice_signal/publish.new/VoiceSignal.staticwebassets.endpoints.json\n")
    expect(build.run!).to eq File.join(publish, 'VoiceSignal')
    expect(File.read(File.join(publish, 'VoiceSignal'))).to eq 'new'
    expect(Dir.children(File.join(root, 'voice_signal'))).to contain_exactly('publish')
    expect(Dir.children(publish)).to eq ['VoiceSignal']
  end
end
