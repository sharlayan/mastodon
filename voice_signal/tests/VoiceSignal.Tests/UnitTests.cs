using System.Collections;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Npgsql;

namespace VoiceSignal.Tests;

public class SecretBoxTests
{
    private const string SecretKeyBase = "test-secret-key-base-0000000000000000000000000000000000000000";
    private const string RubyCiphertext = "v1:AQEBAQEBAQEBAQEBwsZPp/1bcWLdL41uzSA8KWTbZ5QWzN2++Oqd2qwjd1pnH2V4BkRnv2r/2YA/2iCxStf9J8MAWQ==";

    [Fact]
    public void DecryptsSecretsEncryptedByRails()
    {
        Assert.Equal("relay-secret-0123456789abcdefghijklmnop", SecretBox.Decrypt(RubyCiphertext, SecretKeyBase));
    }

    [Fact]
    public void RejectsWrongKeysAndFormats()
    {
        Assert.ThrowsAny<CryptographicException>(() => SecretBox.Decrypt(RubyCiphertext, SecretKeyBase + "x"));
        Assert.ThrowsAny<CryptographicException>(() => SecretBox.Decrypt("v2:" + RubyCiphertext[3..], SecretKeyBase));
        Assert.ThrowsAny<CryptographicException>(() => SecretBox.Decrypt("v1:AQID", SecretKeyBase));
    }
}

public class RelayTokenTests
{
    [Fact]
    public void SignsShortLivedRelayClientTokens()
    {
        var secret = new string('s', 40);
        var token = RelayToken.Create(secret, "https://social.example", "https://voice.example.org", DateTimeOffset.FromUnixTimeSeconds(1_800_000_000));
        var parts = token.Split('.');

        using var header = JsonDocument.Parse(Base64Url.Decode(parts[0]));
        using var payload = JsonDocument.Parse(Base64Url.Decode(parts[1]));
        var expected = Base64Url.Encode(HMACSHA256.HashData(Encoding.UTF8.GetBytes(secret), Encoding.ASCII.GetBytes($"{parts[0]}.{parts[1]}")));

        Assert.Equal("HS256", header.RootElement.GetProperty("alg").GetString());
        Assert.Equal("voice-relay-client+jwt", header.RootElement.GetProperty("typ").GetString());
        Assert.Equal(2, header.RootElement.EnumerateObject().Count());
        Assert.Equal("https://social.example", payload.RootElement.GetProperty("iss").GetString());
        Assert.Equal("https://voice.example.org", payload.RootElement.GetProperty("aud").GetString());
        Assert.Equal(60, payload.RootElement.GetProperty("exp").GetInt64() - payload.RootElement.GetProperty("iat").GetInt64());
        Assert.Equal(4, payload.RootElement.EnumerateObject().Count());
        Assert.Equal(expected, parts[2]);
        Assert.ThrowsAny<CryptographicException>(() => RelayToken.Create("short", "https://a.example", "https://b.example", DateTimeOffset.UtcNow));
    }
}

public class RtcRequestTests
{
    [Theory]
    [InlineData("/voice-signal/rtc?access_token=abc&protocol=16", "/rtc?access_token=abc&protocol=16")]
    [InlineData("/voice-signal/rtc/v1?access_token=abc", "/rtc/v1?access_token=abc")]
    [InlineData("/voice-signal/rtc/validate?access_token=abc", "/rtc/validate?access_token=abc")]
    public void AcceptsRtcPaths(string raw, string suffix)
    {
        Assert.True(RtcRequest.TryParse(raw, "/voice-signal", out var request));
        Assert.Equal(suffix, request.Suffix);
        Assert.Equal("abc", request.AccessToken);
    }

    [Theory]
    [InlineData("/voice-signal/rtc")]
    [InlineData("/voice-signal/rtcx?access_token=abc")]
    [InlineData("/voice-signal/other?access_token=abc")]
    [InlineData("/voice-signal/rtc?access_token=abc&access_token=def")]
    [InlineData("/voice-signal/rtc?access_token=")]
    [InlineData("/voice-signal/rtc/%2e%2e/admin?access_token=abc")]
    [InlineData("/voice-signal/rtc/..%2fadmin?access_token=abc")]
    [InlineData("/voice-signal/rtc/a%5cb?access_token=abc")]
    [InlineData("/voice-signal/rtc/a%252fb?access_token=abc")]
    [InlineData("/voice-signal/rtc/a\\b?access_token=abc")]
    public void RejectsUnsafeOrAmbiguousRequests(string raw)
    {
        Assert.False(RtcRequest.TryParse(raw, "/voice-signal", out _));
    }
}

public class TokenHintTests
{
    public static string LiveKitToken(object metadata) =>
        $"{Base64Url.Encode("{}"u8)}.{Base64Url.Encode(JsonSerializer.SerializeToUtf8Bytes(new { metadata = JsonSerializer.Serialize(metadata) }))}.sig";

    [Fact]
    public void ReadsTheAllocationFromLiveKitMetadata()
    {
        Assert.True(TokenHint.TryParse(LiveKitToken(new { clientId = "c", allocationId = "alloc-1", generation = "g-1", userId = "1" }), out var hint));
        Assert.Equal(new TokenHint("alloc-1", "g-1"), hint);

        Assert.False(TokenHint.TryParse(LiveKitToken(new { allocationId = "../x", generation = "g" }), out _));
        Assert.False(TokenHint.TryParse(LiveKitToken(new { allocationId = "a" }), out _));
        Assert.False(TokenHint.TryParse("not-a-token", out _));
        Assert.False(TokenHint.TryParse("a.%%%.c", out _));
    }
}

public class SignalOptionsTests
{
    private static Hashtable Environment(params (string Key, string Value)[] values)
    {
        var table = new Hashtable { ["LOCAL_DOMAIN"] = "Social.Example.", ["SECRET_KEY_BASE"] = "secret" };
        foreach (var (key, value) in values)
        {
            table[key] = value;
        }

        return table;
    }

    [Fact]
    public void ReadsMastodonEnvironmentDefaults()
    {
        var options = SignalOptions.FromEnvironment(Environment(("WEB_DOMAIN", "web.example")));
        var connection = new NpgsqlConnectionStringBuilder(options.ConnectionString);

        Assert.Equal("https://web.example", options.LocalOrigin);
        Assert.Equal("/voice-signal", options.BasePath);
        Assert.Equal(("localhost", 5432, "mastodon_production", "mastodon"), (connection.Host, connection.Port, connection.Database, connection.Username));
        Assert.Equal(("127.0.0.1", 4100), (options.BindAddress, options.Port));
    }

    [Fact]
    public void PrefersDatabaseUrlAndValidatesValues()
    {
        var options = SignalOptions.FromEnvironment(Environment(("DATABASE_URL", "postgres://user:p%40ss@db.internal:6543/mastodon?sslmode=require"), ("VOICE_SIGNAL_PATH", "voice/")));
        var connection = new NpgsqlConnectionStringBuilder(options.ConnectionString);

        Assert.Equal(("db.internal", 6543, "mastodon", "user", "p@ss", SslMode.Require), (connection.Host, connection.Port, connection.Database, connection.Username, connection.Password, connection.SslMode));
        Assert.Equal("/voice", options.BasePath);
        Assert.Equal("https://social.example", options.LocalOrigin);
        Assert.Throws<InvalidOperationException>(() => SignalOptions.FromEnvironment(Environment(("VOICE_SIGNAL_PATH", "/a/../b"))));
        Assert.Throws<InvalidOperationException>(() => SignalOptions.FromEnvironment(Environment(("VOICE_SIGNAL_PORT", "0"))));
        Assert.Throws<InvalidOperationException>(() => SignalOptions.FromEnvironment(new Hashtable { ["LOCAL_DOMAIN"] = "a.example" }));
    }
}
