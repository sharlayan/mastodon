# frozen_string_literal: true

namespace :voice_signal do
  desc 'Build the voice signal service as a self-contained executable in voice_signal/publish (requires the .NET 10 SDK)'
  task publish: :environment do
    root = File.expand_path('../..', __dir__)
    dotnet = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).map { |directory| File.join(directory, 'dotnet') }.find { |path| File.executable?(path) }
    abort 'The .NET SDK (dotnet) is not installed. Set VOICE_SIGNAL_SPAWN=docker to run the published container image instead.' if dotnet.nil?

    architecture = { 'x86_64' => 'x64', 'amd64' => 'x64', 'aarch64' => 'arm64', 'arm64' => 'arm64' }.fetch(RbConfig::CONFIG['host_cpu']) do
      abort "Unsupported CPU architecture: #{RbConfig::CONFIG['host_cpu']}"
    end
    runtime = File.exist?('/etc/alpine-release') ? "linux-musl-#{architecture}" : "linux-#{architecture}"
    output = File.join(root, 'voice_signal', 'publish')

    FileUtils.rm_rf(output)
    sh dotnet, 'publish', File.join(root, 'voice_signal', 'src', 'VoiceSignal', 'VoiceSignal.csproj'),
       '--configuration', 'Release', '--runtime', runtime, '--self-contained', '--output', output,
       '-p:PublishSingleFile=true', '-p:DebugType=none'
  end
end
