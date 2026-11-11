using System.Net;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.Extensions.Hosting;

namespace VoiceSignal.Tests;

public sealed class ProxyTests : IAsyncLifetime
{
    private const string SecretKeyBase = "test-secret-key-base-0000000000000000000000000000000000000000";
    private const string RubyCiphertext = "v1:AQEBAQEBAQEBAQEBwsZPp/1bcWLdL41uzSA8KWTbZ5QWzN2++Oqd2qwjd1pnH2V4BkRnv2r/2YA/2iCxStf9J8MAWQ==";
    private const string RelaySecret = "relay-secret-0123456789abcdefghijklmnop";

    private readonly List<string> upstreamTargets = [];
    private readonly List<string?> upstreamAuthorizations = [];
    private WebApplication upstream = null!;
    private WebApplication proxy = null!;
    private string upstreamOrigin = null!;
    private string proxyAddress = null!;

    public async Task InitializeAsync()
    {
        var upstreamBuilder = WebApplication.CreateSlimBuilder();
        upstreamBuilder.WebHost.UseUrls("http://127.0.0.1:0");
        upstream = upstreamBuilder.Build();
        upstream.UseWebSockets();
        upstream.Map("/livekit/rtc/{**rest}", async (HttpContext context) =>
        {
            lock (upstreamTargets)
            {
                upstreamTargets.Add(context.Features.Get<IHttpRequestFeature>()!.RawTarget);
                upstreamAuthorizations.Add(context.Request.Headers.Authorization.ToString());
            }

            context.Response.ContentType = "application/json";
            await context.Response.WriteAsync("""{"remote":true}""");
        });
        upstream.Map("/voice-relay/v1/allocations/{id}/{**rest}", async (HttpContext context) =>
        {
            lock (upstreamTargets)
            {
                upstreamTargets.Add(context.Features.Get<IHttpRequestFeature>()!.RawTarget);
                upstreamAuthorizations.Add(context.Request.Headers.Authorization.ToString());
            }

            if ((string?)context.Request.RouteValues["id"] == "alloc-denied")
            {
                context.Response.StatusCode = 403;
                return;
            }

            if (!context.WebSockets.IsWebSocketRequest)
            {
                context.Response.ContentType = "application/json";
                await context.Response.WriteAsync("""{"ok":true}""");
                return;
            }

            using var socket = await context.WebSockets.AcceptWebSocketAsync();
            var buffer = new byte[2 * 1024 * 1024];
            while (true)
            {
                var result = await socket.ReceiveAsync(buffer, CancellationToken.None);
                if (result.MessageType == WebSocketMessageType.Close)
                {
                    await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, null, CancellationToken.None);
                    return;
                }

                await socket.SendAsync(buffer.AsMemory(0, result.Count), result.MessageType, result.EndOfMessage, CancellationToken.None);
            }
        });
        await upstream.StartAsync();
        upstreamOrigin = upstream.Urls.First().TrimEnd('/');

        var options = new SignalOptions
        {
            BasePath = "/voice-signal",
            LocalOrigin = "https://social.example",
            SecretKeyBase = SecretKeyBase,
            ConnectionString = string.Empty,
            AllowInsecureUpstream = true,
        };
        proxy = SignalApp.Build(options, new FakeResolver(upstreamOrigin), "http://127.0.0.1:0");
        await proxy.StartAsync();
        proxyAddress = proxy.Urls.First().TrimEnd('/');
    }

    public async Task DisposeAsync()
    {
        await proxy.StopAsync();
        await upstream.StopAsync();
    }

    private static string Token(string allocationId) => TokenHintTests.LiveKitToken(new { clientId = "c", allocationId, generation = "g-1", userId = "1" });

    [Fact]
    public async Task RelaysWebSocketFramesWithASignedRelayToken()
    {
        var token = Token("alloc-1");
        using var socket = new ClientWebSocket();
        await socket.ConnectAsync(new Uri($"{proxyAddress.Replace("http", "ws")}/voice-signal/rtc?access_token={token}&protocol=16"), CancellationToken.None);

        await socket.SendAsync("ping"u8.ToArray(), WebSocketMessageType.Binary, true, CancellationToken.None);
        var buffer = new byte[64];
        var result = await socket.ReceiveAsync(buffer, CancellationToken.None);
        Assert.Equal("ping", Encoding.UTF8.GetString(buffer, 0, result.Count));
        await socket.CloseAsync(WebSocketCloseStatus.NormalClosure, null, CancellationToken.None);

        Assert.Equal($"/voice-relay/v1/allocations/alloc-1/rtc?access_token={token}&protocol=16", upstreamTargets.Single());
        var bearer = upstreamAuthorizations.Single()!["Bearer ".Length..].Split('.');
        using var payload = JsonDocument.Parse(Base64Url.Decode(bearer[1]));
        Assert.Equal("https://social.example", payload.RootElement.GetProperty("iss").GetString());
        Assert.Equal(upstreamOrigin, payload.RootElement.GetProperty("aud").GetString());
        Assert.Equal(Base64Url.Encode(HMACSHA256.HashData(Encoding.UTF8.GetBytes(RelaySecret), Encoding.ASCII.GetBytes($"{bearer[0]}.{bearer[1]}"))), bearer[2]);
    }

    [Fact]
    public async Task ForwardsValidationRequestsAndUpstreamRejections()
    {
        using var http = new HttpClient();
        var validate = await http.GetAsync($"{proxyAddress}/voice-signal/rtc/validate?access_token={Token("alloc-1")}");
        Assert.Equal(HttpStatusCode.OK, validate.StatusCode);
        Assert.Equal("""{"ok":true}""", await validate.Content.ReadAsStringAsync());

        using var denied = new ClientWebSocket();
        denied.Options.CollectHttpResponseDetails = true;
        await Assert.ThrowsAsync<WebSocketException>(() => denied.ConnectAsync(new Uri($"{proxyAddress.Replace("http", "ws")}/voice-signal/rtc?access_token={Token("alloc-denied")}"), CancellationToken.None));
        Assert.Equal(HttpStatusCode.Forbidden, denied.HttpStatusCode);

        Assert.Equal(HttpStatusCode.Unauthorized, (await http.GetAsync($"{proxyAddress}/voice-signal/rtc?access_token={Token("alloc-unknown")}")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await http.GetAsync($"{proxyAddress}/livekit/rtc/validate?access_token={Token("alloc-1")}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await http.GetAsync($"{proxyAddress}/livekit/federation/token?access_token={Token("alloc-1")}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await http.GetAsync($"{proxyAddress}/voice-signal/rtc/%2e%2e/x?access_token={Token("alloc-1")}")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await http.GetAsync($"{proxyAddress}/voice-signal/health")).StatusCode);
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await http.GetAsync($"{proxyAddress}/voice-signal/rtc?access_token={Token("alloc-db-down")}")).StatusCode);
        Assert.DoesNotContain(upstreamTargets, target => target.Contains("alloc-unknown") || target.Contains("%2e"));
    }

    [Fact]
    public async Task ClosesConnectionsThatSendOversizedMessages()
    {
        using var socket = new ClientWebSocket();
        await socket.ConnectAsync(new Uri($"{proxyAddress.Replace("http", "ws")}/voice-signal/rtc?access_token={Token("alloc-1")}"), CancellationToken.None);

        var chunk = new byte[256 * 1024];
        try
        {
            for (var i = 0; i < 5; i++)
            {
                await socket.SendAsync(chunk, WebSocketMessageType.Binary, i == 4, CancellationToken.None);
            }
        }
        catch (WebSocketException)
        {
        }

        var buffer = new byte[2 * 1024 * 1024];
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        WebSocketReceiveResult? result = null;
        try
        {
            do
            {
                result = await socket.ReceiveAsync(buffer, timeout.Token);
            }
            while (result.MessageType != WebSocketMessageType.Close);
        }
        catch (WebSocketException)
        {
        }

        Assert.True(result is null || result.CloseStatus == WebSocketCloseStatus.MessageTooBig);
        Assert.NotEqual(WebSocketState.Open, socket.State);
    }

    [Fact]
    public async Task ForwardsRemoteCallsToTheRecordedServerWithoutCredentials()
    {
        using var http = new HttpClient();
        var token = TokenHintTests.RemoteToken(new { sub = "https://social.example/users/me", video = new { room = "room-1" } });

        var validate = await http.GetAsync($"{proxyAddress}/voice-signal/remote/rtc/validate?access_token={token}");
        Assert.Equal(HttpStatusCode.OK, validate.StatusCode);
        Assert.Equal("""{"remote":true}""", await validate.Content.ReadAsStringAsync());
        lock (upstreamTargets)
        {
            Assert.Equal($"/livekit/rtc/validate?access_token={token}", upstreamTargets[^1]);
            Assert.Equal(string.Empty, upstreamAuthorizations[^1]);
        }

        var unknown = TokenHintTests.RemoteToken(new { sub = "https://social.example/users/me", video = new { room = "room-2" } });
        Assert.Equal(HttpStatusCode.Unauthorized, (await http.GetAsync($"{proxyAddress}/voice-signal/remote/rtc?access_token={unknown}")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await http.GetAsync($"{proxyAddress}/voice-signal/remote/rtc?access_token={Token("alloc-1")}")).StatusCode);
    }

    private sealed class FakeResolver(string origin) : IAllocationResolver
    {
        public Task<string?> ResolveRemoteOriginAsync(TokenClaims claims, CancellationToken cancellationToken) =>
            Task.FromResult(claims is { Identity: "https://social.example/users/me", Room: "room-1" } ? origin : null);

        public Task<Upstream?> ResolveAsync(TokenHint hint, CancellationToken cancellationToken)
        {
            if (hint.AllocationId == "alloc-db-down")
            {
                throw new FakeDbException();
            }

            return Task.FromResult(hint.AllocationId is "alloc-1" or "alloc-denied" && hint.Generation == "g-1" ? new Upstream(origin, hint.AllocationId, RubyCiphertext) : null);
        }
    }

    private sealed class FakeDbException : System.Data.Common.DbException;
}
