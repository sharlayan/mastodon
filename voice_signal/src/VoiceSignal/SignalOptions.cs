using System.Collections;
using System.Net;
using Npgsql;

namespace VoiceSignal;

public sealed class SignalOptions
{
    public required string BasePath { get; init; }
    public required string LocalOrigin { get; init; }
    public required string SecretKeyBase { get; init; }
    public required string ConnectionString { get; init; }
    public string BindAddress { get; init; } = "127.0.0.1";
    public int Port { get; init; } = 4100;
    public int MaxConnections { get; init; } = 1000;
    public int UpgradesPerMinute { get; init; } = 60;
    public IReadOnlyList<IPNetwork> TrustedProxies { get; init; } = [];
    public bool AllowInsecureUpstream { get; init; }
    public bool ExitOnStdinEof { get; init; }

    public static SignalOptions FromEnvironment(IDictionary environment)
    {
        string? Get(string key) => environment[key] is string value && value.Length > 0 ? value : null;

        var domain = Get("WEB_DOMAIN") ?? Get("LOCAL_DOMAIN") ?? throw new InvalidOperationException("LOCAL_DOMAIN or WEB_DOMAIN is required");
        var secretKeyBase = Get("SECRET_KEY_BASE") ?? throw new InvalidOperationException("SECRET_KEY_BASE is required");

        return new SignalOptions
        {
            BasePath = NormalizeBasePath(Get("VOICE_SIGNAL_PATH") ?? "/voice-signal"),
            LocalOrigin = $"https://{domain.ToLowerInvariant().TrimEnd('.')}",
            SecretKeyBase = secretKeyBase,
            ConnectionString = BuildConnectionString(Get),
            BindAddress = Get("VOICE_SIGNAL_BIND") ?? "127.0.0.1",
            Port = ParseInt("VOICE_SIGNAL_PORT", Get("VOICE_SIGNAL_PORT"), 4100, 1, 65535),
            MaxConnections = ParseInt("VOICE_SIGNAL_MAX_CONNECTIONS", Get("VOICE_SIGNAL_MAX_CONNECTIONS"), 1000, 1, 100_000),
            UpgradesPerMinute = ParseInt("VOICE_SIGNAL_UPGRADES_PER_MINUTE", Get("VOICE_SIGNAL_UPGRADES_PER_MINUTE"), 60, 1, 100_000),
            TrustedProxies = ParseNetworks(Get("VOICE_SIGNAL_TRUSTED_PROXIES")),
            ExitOnStdinEof = Get("VOICE_SIGNAL_EXIT_ON_STDIN_EOF") is "1" or "true",
        };
    }

    public static string NormalizeBasePath(string value)
    {
        var path = "/" + value.Trim().Trim('/');
        if (path == "/" || path.Contains("//") || path.Contains('\\') || path.Contains('%') || path.Contains('?') || path.Split('/').Any(segment => segment is "." or ".."))
        {
            throw new InvalidOperationException("VOICE_SIGNAL_PATH must be a plain absolute path");
        }

        return path;
    }

    private static string BuildConnectionString(Func<string, string?> get)
    {
        var builder = new NpgsqlConnectionStringBuilder
        {
            Host = get("DB_HOST") ?? "localhost",
            Port = ParseInt("DB_PORT", get("DB_PORT"), 5432, 1, 65535),
            Database = get("DB_NAME") ?? "mastodon_production",
            Username = get("DB_USER") ?? "mastodon",
            Password = get("DB_PASS"),
            SslMode = ParseSslMode(get("DB_SSLMODE")),
            MaxPoolSize = ParseInt("VOICE_SIGNAL_DB_POOL", get("VOICE_SIGNAL_DB_POOL"), 5, 1, 100),
            ApplicationName = "voice-signal",
            Timeout = 15,
        };

        var url = get("DATABASE_URL");
        if (url is null)
        {
            return builder.ConnectionString;
        }

        var uri = new Uri(url);
        var credentials = uri.UserInfo.Split(':', 2);
        builder.Host = uri.Host.Length > 0 ? uri.Host : builder.Host;
        builder.Port = uri.Port > 0 ? uri.Port : 5432;
        builder.Database = Uri.UnescapeDataString(uri.AbsolutePath.TrimStart('/'));
        builder.Username = credentials.Length > 0 && credentials[0].Length > 0 ? Uri.UnescapeDataString(credentials[0]) : builder.Username;
        builder.Password = credentials.Length > 1 ? Uri.UnescapeDataString(credentials[1]) : builder.Password;

        foreach (var pair in uri.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = pair.Split('=', 2);
            if (parts.Length != 2)
            {
                continue;
            }

            var value = Uri.UnescapeDataString(parts[1]);
            switch (parts[0])
            {
                case "sslmode":
                    builder.SslMode = ParseSslMode(value);
                    break;
                case "host":
                    builder.Host = value;
                    break;
            }
        }

        return builder.ConnectionString;
    }

    private static SslMode ParseSslMode(string? value) => value switch
    {
        null or "prefer" => SslMode.Prefer,
        "disable" => SslMode.Disable,
        "allow" => SslMode.Allow,
        "require" => SslMode.Require,
        "verify-ca" => SslMode.VerifyCA,
        "verify-full" => SslMode.VerifyFull,
        _ => throw new InvalidOperationException($"Unsupported DB_SSLMODE: {value}"),
    };

    private static int ParseInt(string name, string? value, int fallback, int min, int max)
    {
        if (value is null)
        {
            return fallback;
        }

        if (!int.TryParse(value, out var number) || number < min || number > max)
        {
            throw new InvalidOperationException($"{name} must be an integer between {min} and {max} (got {value})");
        }

        return number;
    }

    private static IReadOnlyList<IPNetwork> ParseNetworks(string? value)
    {
        if (value is null)
        {
            return [];
        }

        return value
            .Split([',', ' '], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(ParseNetwork)
            .ToList();
    }

    private static IPNetwork ParseNetwork(string entry)
    {
        if (entry.Contains('/'))
        {
            if (IPNetwork.TryParse(entry, out var network))
            {
                return network;
            }
        }
        else if (IPAddress.TryParse(entry, out var address))
        {
            return new IPNetwork(address, address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork ? 32 : 128);
        }

        throw new InvalidOperationException($"VOICE_SIGNAL_TRUSTED_PROXIES has an invalid address or network: {entry}");
    }
}
