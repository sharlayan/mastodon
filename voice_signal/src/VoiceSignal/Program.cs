using System.Collections;
using VoiceSignal;

SignalOptions options;
try
{
    options = SignalOptions.FromEnvironment((IDictionary)Environment.GetEnvironmentVariables());
}
catch (Exception exception) when (exception is InvalidOperationException or FormatException or ArgumentException or UriFormatException)
{
    await Console.Error.WriteLineAsync($"voice-signal: {exception.Message}");
    return 2;
}

await SignalApp.Build(options).RunAsync();
return 0;
