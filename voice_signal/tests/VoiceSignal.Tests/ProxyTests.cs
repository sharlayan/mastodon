using System.Net;
using System.Net.Sockets;
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
    private FakeResolver resolver = null!;

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

            if (context.WebSockets.IsWebSocketRequest)
            {
                using var socket = await context.WebSockets.AcceptWebSocketAsync();
                var buffer = new byte[64];
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
        resolver = new FakeResolver(upstreamOrigin);
        proxy = SignalApp.Build(options, resolver, "http://127.0.0.1:0");
        await proxy.StartAsync();
        proxyAddress = proxy.Urls.First().TrimEnd('/');
    }

    public async Task DisposeAsync()
    {
        await proxy.StopAsync();
        await upstream.StopAsync();
    }

    private static string Token(string allocationId, string userId = "1") => TokenHintTests.LiveKitToken(new { clientId = "c", allocationId, generation = "g-1", userId });

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
        var targets = upstreamTargets.Count;
        Assert.Equal(HttpStatusCode.Forbidden, (await http.GetAsync($"{proxyAddress}/voice-signal/rtc/validate?access_token={Token("alloc-1", "2")}")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await http.GetAsync($"{proxyAddress}/livekit/rtc/validate?access_token={Token("alloc-1", "2")}")).StatusCode);
        using var outsider = new ClientWebSocket();
        outsider.Options.CollectHttpResponseDetails = true;
        await Assert.ThrowsAsync<WebSocketException>(() => outsider.ConnectAsync(new Uri($"{proxyAddress.Replace("http", "ws")}/voice-signal/rtc?access_token={Token("alloc-1", "2")}"), CancellationToken.None));
        Assert.Equal(HttpStatusCode.Forbidden, outsider.HttpStatusCode);
        Assert.Equal(targets, upstreamTargets.Count);
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
    public async Task ClosesAnOpenRemoteSignalAndRejectsReconnectAfterAdmissionIsRevoked()
    {
        var token = TokenHintTests.RemoteToken(new { sub = "https://social.example/users/me", video = new { room = "room-1" } });
        using var socket = new ClientWebSocket();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        await socket.ConnectAsync(new Uri($"{proxyAddress.Replace("http", "ws")}/voice-signal/remote/7/rtc?access_token={token}"), deadline.Token);
        await socket.SendAsync("ping"u8.ToArray(), WebSocketMessageType.Binary, true, deadline.Token);
        var buffer = new byte[64];
        var echoed = await socket.ReceiveAsync(buffer, deadline.Token);
        Assert.Equal("ping", Encoding.UTF8.GetString(buffer, 0, echoed.Count));

        resolver.AllowRemoteCalls = false;
        try
        {
            var closed = await socket.ReceiveAsync(buffer, deadline.Token);
            Assert.Equal(WebSocketMessageType.Close, closed.MessageType);
        }
        catch (WebSocketException)
        {
        }
        Assert.NotEqual(WebSocketState.Open, socket.State);

        using var http = new HttpClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await http.GetAsync($"{proxyAddress}/voice-signal/remote/7/rtc/validate?access_token={token}", deadline.Token)).StatusCode);
    }

    [Theory]
    [InlineData("screen_share")]
    [InlineData("screen_share_audio")]
    public async Task RevokesScreenTokensWithoutClosingMicrophoneOnlyConnections(string screenSource)
    {
        var screenToken = TokenHintTests.RemoteToken(new { sub = "https://social.example/users/me", video = new { room = "room-1", canPublish = true, canPublishSources = new[] { "microphone", screenSource } } });
        var microphoneToken = TokenHintTests.RemoteToken(new { sub = "https://social.example/users/me", video = new { room = "room-1", canPublish = true, canPublishSources = new[] { "microphone" } } });
        using var screen = new ClientWebSocket();
        using var microphone = new ClientWebSocket();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        var socketAddress = proxyAddress.Replace("http", "ws");
        await screen.ConnectAsync(new Uri($"{socketAddress}/voice-signal/remote/7/rtc?access_token={screenToken}"), deadline.Token);
        await microphone.ConnectAsync(new Uri($"{socketAddress}/voice-signal/remote/7/rtc?access_token={microphoneToken}"), deadline.Token);

        resolver.AllowScreenSharing = false;
        var buffer = new byte[64];
        try
        {
            var closed = await screen.ReceiveAsync(buffer, deadline.Token);
            Assert.Equal(WebSocketMessageType.Close, closed.MessageType);
        }
        catch (WebSocketException)
        {
        }
        Assert.NotEqual(WebSocketState.Open, screen.State);

        await microphone.SendAsync("ping"u8.ToArray(), WebSocketMessageType.Binary, true, deadline.Token);
        var echoed = await microphone.ReceiveAsync(buffer, deadline.Token);
        Assert.Equal("ping", Encoding.UTF8.GetString(buffer, 0, echoed.Count));
        await microphone.CloseAsync(WebSocketCloseStatus.NormalClosure, null, deadline.Token);

        using var http = new HttpClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await http.GetAsync($"{proxyAddress}/voice-signal/remote/7/rtc/validate?access_token={screenToken}", deadline.Token)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await http.GetAsync($"{proxyAddress}/voice-signal/remote/7/rtc/validate?access_token={microphoneToken}", deadline.Token)).StatusCode);
    }

    [Fact]
    public async Task ForwardsRemoteCallsToTheRecordedServerWithoutCredentials()
    {
        using var http = new HttpClient();
        var token = TokenHintTests.RemoteToken(new { sub = "https://social.example/users/me", video = new { room = "room-1" } });

        var validate = await http.GetAsync($"{proxyAddress}/voice-signal/remote/7/rtc/validate?access_token={token}");
        Assert.Equal(HttpStatusCode.OK, validate.StatusCode);
        Assert.Equal("""{"remote":true}""", await validate.Content.ReadAsStringAsync());
        Assert.Equal("text/plain", validate.Content.Headers.ContentType?.MediaType);
        Assert.Equal("nosniff", validate.Headers.GetValues("X-Content-Type-Options").Single());
        Assert.StartsWith("default-src 'none'", validate.Headers.GetValues("Content-Security-Policy").Single());
        lock (upstreamTargets)
        {
            Assert.Equal($"/livekit/rtc/validate?access_token={token}", upstreamTargets[^1]);
            Assert.Equal(string.Empty, upstreamAuthorizations[^1]);
        }

        var unknown = TokenHintTests.RemoteToken(new { sub = "https://social.example/users/me", video = new { room = "room-2" } });
        Assert.Equal(HttpStatusCode.Unauthorized, (await http.GetAsync($"{proxyAddress}/voice-signal/remote/7/rtc?access_token={unknown}")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await http.GetAsync($"{proxyAddress}/voice-signal/remote/8/rtc?access_token={token}")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await http.GetAsync($"{proxyAddress}/voice-signal/remote/7/rtc?access_token={Token("alloc-1")}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await http.GetAsync($"{proxyAddress}/voice-signal/remote/rtc?access_token={token}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await http.GetAsync($"{proxyAddress}/voice-signal/remote/-7/rtc?access_token={token}")).StatusCode);
    }

    [Fact]
    public async Task LimitsConcurrentConnectionsFromOneAddress()
    {
        var options = new SignalOptions
        {
            BasePath = "/voice-signal",
            LocalOrigin = "https://social.example",
            SecretKeyBase = SecretKeyBase,
            ConnectionString = string.Empty,
            AllowInsecureUpstream = true,
            MaxConnectionsPerAddress = 1,
        };
        var limited = SignalApp.Build(options, new FakeResolver(upstreamOrigin), "http://127.0.0.1:0");
        await limited.StartAsync();
        try
        {
            var address = limited.Urls.First().TrimEnd('/').Replace("http", "ws");
            using var first = new ClientWebSocket();
            await first.ConnectAsync(new Uri($"{address}/voice-signal/rtc?access_token={Token("alloc-1")}"), CancellationToken.None);

            using var second = new ClientWebSocket();
            second.Options.CollectHttpResponseDetails = true;
            await Assert.ThrowsAsync<WebSocketException>(() => second.ConnectAsync(new Uri($"{address}/voice-signal/rtc?access_token={Token("alloc-1")}"), CancellationToken.None));
            Assert.Equal(HttpStatusCode.ServiceUnavailable, second.HttpStatusCode);

            using var federated = new ClientWebSocket();
            await federated.ConnectAsync(new Uri($"{address}/livekit/rtc?access_token={Token("alloc-1")}"), CancellationToken.None);
            using var federatedAgain = new ClientWebSocket();
            await federatedAgain.ConnectAsync(new Uri($"{address}/livekit/rtc?access_token={Token("alloc-1")}"), CancellationToken.None);
            await federated.CloseAsync(WebSocketCloseStatus.NormalClosure, null, CancellationToken.None);
            await federatedAgain.CloseAsync(WebSocketCloseStatus.NormalClosure, null, CancellationToken.None);

            await first.CloseAsync(WebSocketCloseStatus.NormalClosure, null, CancellationToken.None);
            for (var attempt = 0; ; attempt++)
            {
                try
                {
                    using var retry = new ClientWebSocket();
                    await retry.ConnectAsync(new Uri($"{address}/voice-signal/rtc?access_token={Token("alloc-1")}"), CancellationToken.None);
                    await retry.CloseAsync(WebSocketCloseStatus.NormalClosure, null, CancellationToken.None);
                    break;
                }
                catch (WebSocketException) when (attempt < 20)
                {
                    await Task.Delay(100);
                }
            }
        }
        finally
        {
            await limited.StopAsync();
        }
    }

    [Fact]
    public async Task RateLimitsClientsBehindTrustedProxiesByNetwork()
    {
        var options = new SignalOptions
        {
            BasePath = "/voice-signal",
            LocalOrigin = "https://social.example",
            SecretKeyBase = SecretKeyBase,
            ConnectionString = string.Empty,
            AllowInsecureUpstream = true,
            UpgradesPerMinute = 1,
            TrustedProxies = [IPNetwork.Parse("10.0.0.0/8")],
        };
        var limited = SignalApp.Build(options, new FakeResolver(upstreamOrigin), "http://127.0.0.1:0");
        await limited.StartAsync();
        try
        {
            using var client = new HttpClient();
            async Task<HttpStatusCode> From(string forwardedFor)
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, $"{limited.Urls.First().TrimEnd('/')}/voice-signal/rtc?access_token=invalid");
                request.Headers.Add("X-Forwarded-For", forwardedFor);
                return (await client.SendAsync(request)).StatusCode;
            }

            Assert.Equal(HttpStatusCode.Unauthorized, await From("2001:db8::1, 10.0.0.1"));
            Assert.Equal(HttpStatusCode.TooManyRequests, await From("2001:db8::2, 10.0.0.1"));
            Assert.Equal(HttpStatusCode.Unauthorized, await From("2001:db8:1::1, 10.0.0.1"));
        }
        finally
        {
            await limited.StopAsync();
        }
    }

    [Fact]
    public async Task ClosesOpenCallsWhenStopping()
    {
        var options = new SignalOptions
        {
            BasePath = "/voice-signal",
            LocalOrigin = "https://social.example",
            SecretKeyBase = SecretKeyBase,
            ConnectionString = string.Empty,
            AllowInsecureUpstream = true,
        };
        var stopping = SignalApp.Build(options, new FakeResolver(upstreamOrigin), "http://127.0.0.1:0");
        await stopping.StartAsync();

        using var socket = new ClientWebSocket();
        await socket.ConnectAsync(new Uri($"{stopping.Urls.First().TrimEnd('/').Replace("http", "ws")}/voice-signal/rtc?access_token={Token("alloc-1")}"), CancellationToken.None);

        var watch = System.Diagnostics.Stopwatch.StartNew();
        await stopping.StopAsync();
        Assert.True(watch.Elapsed < TimeSpan.FromSeconds(10), $"stopping took {watch.Elapsed}");
    }

    [Fact]
    public async Task SendsRelayAndRemoteConnectionsThroughTheConfiguredProxyWithoutLocalLookups()
    {
        await using var forward = new FakeForwardProxy(new Uri(upstreamOrigin).Port);
        var options = new SignalOptions
        {
            BasePath = "/voice-signal",
            LocalOrigin = "https://social.example",
            SecretKeyBase = SecretKeyBase,
            ConnectionString = string.Empty,
            AllowInsecureUpstream = true,
            OutboundProxy = forward.Address,
        };
        var proxied = SignalApp.Build(options, new FakeResolver($"http://relay.test:{new Uri(upstreamOrigin).Port}"), "http://127.0.0.1:0");
        await proxied.StartAsync();
        try
        {
            var address = proxied.Urls.First().TrimEnd('/');
            using var socket = new ClientWebSocket();
            await socket.ConnectAsync(new Uri($"{address.Replace("http", "ws")}/voice-signal/rtc?access_token={Token("alloc-1")}"), CancellationToken.None);
            await socket.SendAsync("ping"u8.ToArray(), WebSocketMessageType.Binary, true, CancellationToken.None);
            var buffer = new byte[64];
            var result = await socket.ReceiveAsync(buffer, CancellationToken.None);
            Assert.Equal("ping", Encoding.UTF8.GetString(buffer, 0, result.Count));
            await socket.CloseAsync(WebSocketCloseStatus.NormalClosure, null, CancellationToken.None);

            using var http = new HttpClient();
            Assert.Equal(HttpStatusCode.OK, (await http.GetAsync($"{address}/voice-signal/rtc/validate?access_token={Token("alloc-1")}")).StatusCode);
            var remote = TokenHintTests.RemoteToken(new { sub = "https://social.example/users/me", video = new { room = "room-1" } });
            var validate = await http.GetAsync($"{address}/voice-signal/remote/7/rtc/validate?access_token={remote}");
            Assert.Equal(HttpStatusCode.OK, validate.StatusCode);
            Assert.Equal("""{"remote":true}""", await validate.Content.ReadAsStringAsync());

            Assert.NotEmpty(forward.RequestLines);
            Assert.All(forward.RequestLines, line => Assert.Contains("relay.test", line));
        }
        finally
        {
            await proxied.StopAsync();
        }
    }

    private sealed class FakeResolver(string origin) : IAllocationResolver
    {
        public volatile bool AllowRemoteCalls = true;
        public volatile bool AllowScreenSharing = true;

        public Task<bool> IsAdmittedAsync(TokenHint hint, CancellationToken cancellationToken) => Task.FromResult(hint.UserId == 1);

        public Task<string?> ResolveRemoteOriginAsync(long sessionId, TokenClaims claims, CancellationToken cancellationToken) =>
            Task.FromResult(AllowRemoteCalls && (!claims.CanPublishScreenShare || AllowScreenSharing) && sessionId == 7 && claims is { Identity: "https://social.example/users/me", Room: "room-1" } ? origin : null);

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

    private sealed class FakeForwardProxy : IAsyncDisposable
    {
        private readonly TcpListener listener = new(IPAddress.Loopback, 0);
        private readonly CancellationTokenSource stopping = new();
        private readonly int upstreamPort;
        private readonly Task accepting;

        public FakeForwardProxy(int upstreamPort)
        {
            this.upstreamPort = upstreamPort;
            listener.Start();
            accepting = AcceptAsync();
        }

        public List<string> RequestLines { get; } = [];

        public Uri Address => new($"http://127.0.0.1:{((IPEndPoint)listener.LocalEndpoint).Port}");

        public async ValueTask DisposeAsync()
        {
            await stopping.CancelAsync();
            listener.Stop();
            await accepting;
        }

        private async Task AcceptAsync()
        {
            while (!stopping.IsCancellationRequested)
            {
                TcpClient client;
                try
                {
                    client = await listener.AcceptTcpClientAsync(stopping.Token);
                }
                catch (Exception exception) when (exception is OperationCanceledException or SocketException or ObjectDisposedException)
                {
                    return;
                }

                _ = HandleAsync(client);
            }
        }

        private async Task HandleAsync(TcpClient client)
        {
            using (client)
            using (var upstream = new TcpClient())
            {
                var downstream = client.GetStream();
                var head = new List<byte>();
                var one = new byte[1];
                while (head.Count < 16 * 1024 && !(head.Count >= 4 && head[^4] == '\r' && head[^3] == '\n' && head[^2] == '\r' && head[^1] == '\n'))
                {
                    if (await downstream.ReadAsync(one) == 0)
                    {
                        return;
                    }

                    head.Add(one[0]);
                }

                var text = Encoding.ASCII.GetString(head.ToArray());
                var line = text[..text.IndexOf("\r\n", StringComparison.Ordinal)];
                lock (RequestLines)
                {
                    RequestLines.Add(line);
                }

                await upstream.ConnectAsync(IPAddress.Loopback, upstreamPort);
                var upstreamStream = upstream.GetStream();
                if (line.StartsWith("CONNECT ", StringComparison.Ordinal))
                {
                    await downstream.WriteAsync("HTTP/1.1 200 Connection established\r\n\r\n"u8.ToArray());
                }
                else
                {
                    await upstreamStream.WriteAsync(head.ToArray());
                }

                try
                {
                    await Task.WhenAny(downstream.CopyToAsync(upstreamStream), upstreamStream.CopyToAsync(downstream));
                }
                catch (IOException)
                {
                }
            }
        }
    }
}
