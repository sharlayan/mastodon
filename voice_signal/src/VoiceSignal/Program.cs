using System.Collections;
using VoiceSignal;

var options = SignalOptions.FromEnvironment((IDictionary)Environment.GetEnvironmentVariables());
await SignalApp.Build(options).RunAsync();
