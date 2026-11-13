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

    public static string RemoteToken(object claims) =>
        $"{Base64Url.Encode("{}"u8)}.{Base64Url.Encode(JsonSerializer.SerializeToUtf8Bytes(claims))}.sig";

    [Fact]
    public void ReadsTheIdentityAndRoomOfARemoteToken()
    {
        Assert.True(TokenClaims.TryParse(RemoteToken(new { sub = "https://social.example/users/me", video = new { room = "room-1", roomJoin = true } }), out var claims));
        Assert.Equal(new TokenClaims("https://social.example/users/me", "room-1"), claims);

        Assert.False(TokenClaims.TryParse(RemoteToken(new { sub = "https://social.example/users/me" }), out _));
        Assert.False(TokenClaims.TryParse(RemoteToken(new { sub = 1, video = new { room = "room-1" } }), out _));
        Assert.False(TokenClaims.TryParse("not-a-token", out _));
    }

    [Theory]
    [InlineData("{}", true)]
    [InlineData("{\"canPublish\":null}", true)]
    [InlineData("{\"canPublish\":false}", false)]
    [InlineData("{\"canPublishSources\":null}", true)]
    [InlineData("{\"canPublishSources\":[]}", true)]
    [InlineData("{\"canPublishSources\":[\"microphone\"]}", false)]
    [InlineData("{\"canPublishSources\":[\"camera\",\"microphone\"]}", false)]
    [InlineData("{\"canPublishSources\":[\"screen_share\"]}", true)]
    [InlineData("{\"canPublishSources\":[\"screen_share_audio\"]}", true)]
    [InlineData("{\"canPublish\":false,\"canPublishSources\":[\"screen_share\",\"screen_share_audio\"]}", false)]
    public void ReadsScreenSharingPermissionFromRemoteTokenGrants(string grant, bool expected)
    {
        var video = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(grant)!;
        video["room"] = JsonSerializer.SerializeToElement("room-1");
        var token = RemoteToken(new { sub = "https://social.example/users/me", video });

        Assert.True(TokenClaims.TryParse(token, out var claims));
        Assert.Equal(expected, claims!.CanPublishScreenShare);
    }

    [Theory]
    [InlineData("{\"canPublish\":\"true\"}")]
    [InlineData("{\"canPublishSources\":\"screen_share\"}")]
    [InlineData("{\"canPublishSources\":[3]}")]
    public void RejectsRemoteTokensWithMalformedPublishGrants(string grant)
    {
        var video = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(grant)!;
        video["room"] = JsonSerializer.SerializeToElement("room-1");
        Assert.False(TokenClaims.TryParse(RemoteToken(new { sub = "https://social.example/users/me", video }), out _));
    }

    [Theory]
    [InlineData("[]")]
    [InlineData("null")]
    [InlineData("1")]
    [InlineData("true")]
    [InlineData("\"text\"")]
    public void RejectsNonObjectTokenPayloads(string payload)
    {
        var token = $"{Base64Url.Encode("{}"u8)}.{Base64Url.Encode(Encoding.UTF8.GetBytes(payload))}.sig";
        Assert.False(TokenHint.TryParse(token, out _));
        Assert.False(TokenClaims.TryParse(token, out _));
    }

    [Fact]
    public void ReadsTheAllocationFromLiveKitMetadata()
    {
        Assert.True(TokenHint.TryParse(LiveKitToken(new { clientId = "c", allocationId = "alloc-1", generation = "g-1", userId = "1" }), out var hint));
        Assert.Equal(new TokenHint("alloc-1", "g-1", 1), hint);

        Assert.False(TokenHint.TryParse(LiveKitToken(new { allocationId = "alloc-1", generation = "g-1" }), out _));
        Assert.False(TokenHint.TryParse(LiveKitToken(new { allocationId = "alloc-1", generation = "g-1", userId = "01" }), out _));
        Assert.False(TokenHint.TryParse(LiveKitToken(new { allocationId = "alloc-1", generation = "g-1", userId = 1 }), out _));

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
        Assert.Throws<InvalidOperationException>(() => SignalOptions.FromEnvironment(Environment(("WEB_DOMAIN", "web.example"), ("VOICE_SIGNAL_PATH", "/livekit"))));
        Assert.Equal(("localhost", 5432, "mastodon_production", "mastodon"), (connection.Host, connection.Port, connection.Database, connection.Username));
        Assert.Equal(("127.0.0.1", 4100), (options.BindAddress, options.Port));
        Assert.False(options.ExitOnStdinEof);
        Assert.False(options.RoleplayMode);
        Assert.True(SignalOptions.FromEnvironment(Environment(("OC_ROLEPLAY_OPTION", "true"))).RoleplayMode);
        Assert.True(SignalOptions.FromEnvironment(Environment(("VOICE_SIGNAL_EXIT_ON_STDIN_EOF", "1"))).ExitOnStdinEof);
    }

    [Fact]
    public void PrefersDatabaseUrlAndValidatesValues()
    {
        var options = SignalOptions.FromEnvironment(Environment(("DATABASE_URL", "postgres://user:p%40ss@db.internal:6543/mastodon?sslmode=require"), ("VOICE_SIGNAL_PATH", "voice/")));
        var connection = new NpgsqlConnectionStringBuilder(options.ConnectionString);

        Assert.Equal(("db.internal", 6543, "mastodon", "user", "p@ss", SslMode.Require), (connection.Host, connection.Port, connection.Database, connection.Username, connection.Password, connection.SslMode));
        Assert.Equal("/voice", options.BasePath);

        var socket = new NpgsqlConnectionStringBuilder(SignalOptions.FromEnvironment(Environment(("DATABASE_URL", "postgres:///mastodon?host=%2Fvar%2Frun%2Fpostgresql"))).ConnectionString);
        Assert.Equal(("/var/run/postgresql", "mastodon"), (socket.Host, socket.Database));
        Assert.Equal("https://social.example", options.LocalOrigin);
        Assert.Throws<InvalidOperationException>(() => SignalOptions.FromEnvironment(Environment(("VOICE_SIGNAL_PATH", "/a/../b"))));
        Assert.Contains("VOICE_SIGNAL_PORT", Assert.Throws<InvalidOperationException>(() => SignalOptions.FromEnvironment(Environment(("VOICE_SIGNAL_PORT", "0")))).Message);
        Assert.Contains("not-an-ip", Assert.Throws<InvalidOperationException>(() => SignalOptions.FromEnvironment(Environment(("VOICE_SIGNAL_TRUSTED_PROXIES", "10.0.0.0/8, not-an-ip")))).Message);
        Assert.Equal(2, SignalOptions.FromEnvironment(Environment(("VOICE_SIGNAL_TRUSTED_PROXIES", "10.0.0.0/8 127.0.0.2"))).TrustedProxies.Count);
        Assert.Throws<InvalidOperationException>(() => SignalOptions.FromEnvironment(new Hashtable { ["LOCAL_DOMAIN"] = "a.example" }));
    }
    [Fact]
    public void ReadsTheOutboundProxyFromTheSameVariableAsMastodon()
    {
        Assert.Null(SignalOptions.FromEnvironment(Environment()).OutboundProxy);
        Assert.Null(SignalOptions.FromEnvironment(Environment(("HTTP_PROXY", "http://upper.example:3128"), ("https_proxy", "http://secure.example:3128"))).OutboundProxy);
        Assert.Equal(new Uri("http://10.200.0.1:8128"), SignalOptions.FromEnvironment(Environment(("http_proxy", "http://10.200.0.1:8128"))).OutboundProxy);
        Assert.Equal("https", SignalOptions.FromEnvironment(Environment(("http_proxy", "https://user:p%40ss@proxy.example:443"))).OutboundProxy!.Scheme);
        Assert.Contains("http_proxy", Assert.Throws<InvalidOperationException>(() => SignalOptions.FromEnvironment(Environment(("http_proxy", "socks5://proxy.example:1080")))).Message);
        Assert.Throws<InvalidOperationException>(() => SignalOptions.FromEnvironment(Environment(("http_proxy", "proxy.example:3128"))));
    }
}

public class OutboundConnectionsTests
{
    private static SignalOptions Options(Uri? proxy) => new()
    {
        BasePath = "/voice-signal",
        LocalOrigin = "https://social.example",
        SecretKeyBase = "secret",
        ConnectionString = string.Empty,
        OutboundProxy = proxy,
    };

    [Fact]
    public void ConnectsDirectlyWithoutAProxyAndIgnoresProxyEnvironmentVariables()
    {
        using var relay = OutboundConnections.CreateRelayHandler(Options(null));
        using var remote = OutboundConnections.CreateRemoteHandler(Options(null));

        Assert.False(relay.UseProxy);
        Assert.False(remote.UseProxy);
        Assert.NotNull(remote.ConnectCallback);
    }

    [Fact]
    public void SendsRelayAndRemoteConnectionsThroughTheProxyAndLeavesLookupsToIt()
    {
        var options = Options(new Uri("http://user:p%40ss@10.200.0.1:8128/ignored"));
        using var relay = OutboundConnections.CreateRelayHandler(options);
        using var remote = OutboundConnections.CreateRemoteHandler(options);
        var target = new Uri("https://remote.example/livekit/rtc");

        foreach (var handler in new[] { relay, remote })
        {
            Assert.True(handler.UseProxy);
            Assert.False(handler.AllowAutoRedirect);
            Assert.Null(handler.ConnectCallback);
            Assert.Equal(new Uri("http://10.200.0.1:8128/"), handler.Proxy!.GetProxy(target));
            Assert.False(handler.Proxy.IsBypassed(new Uri("http://127.0.0.1/")));
            var credential = handler.Proxy.Credentials!.GetCredential(target, "Basic")!;
            Assert.Equal(("user", "p@ss"), (credential.UserName, credential.Password));
        }
    }
}

public class PublicAddressConnectorTests
{
    [Theory]
    [InlineData("127.0.0.1", false)]
    [InlineData("10.1.2.3", false)]
    [InlineData("172.20.0.1", false)]
    [InlineData("192.168.1.1", false)]
    [InlineData("169.254.169.254", false)]
    [InlineData("100.64.0.1", false)]
    [InlineData("0.0.0.0", false)]
    [InlineData("::1", false)]
    [InlineData("fd00::1", false)]
    [InlineData("fe80::1", false)]
    [InlineData("::ffff:10.0.0.1", false)]
    [InlineData("::10.0.0.1", false)]
    [InlineData("64:ff9b::a00:5", false)]
    [InlineData("64:ff9b:1::1", false)]
    [InlineData("2002:a00:1::1", false)]
    [InlineData("2001:db8::1", false)]
    [InlineData("100::1", false)]
    [InlineData("203.0.113.9", false)]
    [InlineData("255.255.255.255", false)]
    [InlineData("93.184.216.34", true)]
    [InlineData("172.32.0.1", true)]
    [InlineData("2606:4700::1111", true)]
    public void AllowsOnlyPublicAddresses(string address, bool expected)
    {
        Assert.Equal(expected, PublicAddressConnector.IsPublic(System.Net.IPAddress.Parse(address)));
    }
}
