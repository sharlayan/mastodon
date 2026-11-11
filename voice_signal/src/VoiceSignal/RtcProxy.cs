using System.Buffers;
using System.Collections.Concurrent;
using System.Data.Common;
using System.Net;
using System.Net.WebSockets;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Http.Features;

namespace VoiceSignal;

public sealed class RtcProxy(SignalOptions options, IAllocationResolver resolver, IHttpClientFactory httpClientFactory, ILogger<RtcProxy> logger)
{
    public const string HttpClientName = "relay";
    public const int MaxMessageBytes = 1024 * 1024;

    private static readonly TimeSpan ConnectTimeout = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan KeepAliveInterval = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan KeepAliveTimeout = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan CloseTimeout = TimeSpan.FromSeconds(5);
    private static readonly string[] ForwardedHeaders = ["Accept", "User-Agent"];

    private readonly SemaphoreSlim connections = new(options.MaxConnections, options.MaxConnections);
    private readonly ConcurrentDictionary<string, int> addressConnections = new();
    private readonly HttpMessageInvoker remoteInvoker = new(PublicAddressConnector.CreateHandler(options.AllowInsecureUpstream), disposeHandler: true);

    public async Task HandleAsync(HttpContext context)
    {
        var rawTarget = context.Features.Get<IHttpRequestFeature>()?.RawTarget ?? string.Empty;
        if (!RtcRequest.TryParse(rawTarget, options.BasePath, out var rtc) && !RtcRequest.TryParse(rawTarget, options.FederationPath, out rtc))
        {
            context.Response.StatusCode = StatusCodes.Status404NotFound;
            return;
        }

        if (!HttpMethods.IsGet(context.Request.Method))
        {
            context.Response.StatusCode = StatusCodes.Status405MethodNotAllowed;
            return;
        }

        if (!TokenHint.TryParse(rtc.AccessToken, out var hint))
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            return;
        }

        Upstream? upstream;
        try
        {
            upstream = await resolver.ResolveAsync(hint, context.RequestAborted);
        }
        catch (DbException exception)
        {
            logger.LogError(exception, "Could not look up the voice call allocation");
            context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
            return;
        }

        if (upstream is null || !TryBuildTarget(upstream, rtc, out var target))
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            return;
        }

        string bearer;
        try
        {
            bearer = RelayToken.Create(SecretBox.Decrypt(upstream.SecretCiphertext, options.SecretKeyBase), options.LocalOrigin, upstream.Origin, DateTimeOffset.UtcNow);
        }
        catch (Exception exception) when (exception is CryptographicException or FormatException)
        {
            logger.LogError("The relay secret for {Origin} cannot be decrypted; re-enter it in the admin settings", upstream.Origin);
            context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
            return;
        }

        var address = AddressKey(context);
        if (!TryAcquire(address))
        {
            context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
            return;
        }

        try
        {
            if (context.WebSockets.IsWebSocketRequest)
            {
                await ProxyWebSocketAsync(context, target, bearer);
            }
            else
            {
                await ProxyHttpAsync(context, target, bearer);
            }
        }
        finally
        {
            Release(address);
        }
    }

    public async Task HandleRemoteAsync(HttpContext context)
    {
        var rawTarget = context.Features.Get<IHttpRequestFeature>()?.RawTarget ?? string.Empty;
        if (!RtcRequest.TryParse(rawTarget, options.RemotePath, out var rtc))
        {
            context.Response.StatusCode = StatusCodes.Status404NotFound;
            return;
        }

        if (!HttpMethods.IsGet(context.Request.Method))
        {
            context.Response.StatusCode = StatusCodes.Status405MethodNotAllowed;
            return;
        }

        if (!TokenClaims.TryParse(rtc.AccessToken, out var claims))
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            return;
        }

        string? origin;
        try
        {
            origin = await resolver.ResolveRemoteOriginAsync(claims, context.RequestAborted);
        }
        catch (DbException exception)
        {
            logger.LogError(exception, "Could not look up the remote voice call session");
            context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
            return;
        }

        if (origin is null || !TryBuildRemoteTarget(origin, rtc, out var target))
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            return;
        }

        var address = AddressKey(context);
        if (!TryAcquire(address))
        {
            context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
            return;
        }

        try
        {
            if (context.WebSockets.IsWebSocketRequest)
            {
                await ProxyWebSocketAsync(context, target, null, remoteInvoker);
            }
            else
            {
                await ProxyHttpAsync(context, target, null, remoteInvoker);
            }
        }
        finally
        {
            Release(address);
        }
    }

    private static string AddressKey(HttpContext context)
    {
        var address = context.Connection.RemoteIpAddress;
        if (address is null)
        {
            return string.Empty;
        }

        if (address.IsIPv4MappedToIPv6)
        {
            address = address.MapToIPv4();
        }

        if (address.AddressFamily != System.Net.Sockets.AddressFamily.InterNetworkV6)
        {
            return address.ToString();
        }

        var bytes = address.GetAddressBytes();
        Array.Clear(bytes, 8, 8);
        return new IPAddress(bytes).ToString();
    }

    private bool TryAcquire(string address)
    {
        if (!connections.Wait(0))
        {
            return false;
        }

        if (addressConnections.AddOrUpdate(address, 1, (_, count) => count + 1) <= options.MaxConnectionsPerAddress)
        {
            return true;
        }

        Release(address);
        return false;
    }

    private void Release(string address)
    {
        while (addressConnections.TryGetValue(address, out var count))
        {
            if (count <= 1 ? addressConnections.TryRemove(new KeyValuePair<string, int>(address, count)) : addressConnections.TryUpdate(address, count - 1, count))
            {
                break;
            }
        }

        connections.Release();
    }

    private bool TryBuildRemoteTarget(string remoteOrigin, RtcRequest rtc, out Uri target)
    {
        target = null!;

        if (!TryParseOrigin(remoteOrigin, out var origin)
            || !Uri.TryCreate($"{origin.GetLeftPart(UriPartial.Authority)}{options.FederationPath}{rtc.Suffix}", UriKind.Absolute, out var built)
            || built.GetLeftPart(UriPartial.Authority) != origin.GetLeftPart(UriPartial.Authority))
        {
            return false;
        }

        target = built;
        return true;
    }

    private bool TryParseOrigin(string value, out Uri origin)
    {
        return Uri.TryCreate(value, UriKind.Absolute, out origin!)
            && (origin.Scheme == Uri.UriSchemeHttps || (options.AllowInsecureUpstream && origin.Scheme == Uri.UriSchemeHttp))
            && origin.AbsolutePath == "/" && origin.Query.Length == 0 && origin.UserInfo.Length == 0;
    }

    private bool TryBuildTarget(Upstream upstream, RtcRequest rtc, out Uri target)
    {
        target = null!;

        if (!TryParseOrigin(upstream.Origin, out var origin))
        {
            return false;
        }

        if (!Uri.TryCreate($"{origin.GetLeftPart(UriPartial.Authority)}/voice-relay/v1/allocations/{upstream.RemoteId}{rtc.Suffix}", UriKind.Absolute, out var built)
            || built.GetLeftPart(UriPartial.Authority) != origin.GetLeftPart(UriPartial.Authority))
        {
            return false;
        }

        target = built;
        return true;
    }

    private async Task ProxyHttpAsync(HttpContext context, Uri target, string? bearer, HttpMessageInvoker? invoker = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, target);
        if (bearer is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {bearer}");
        }

        foreach (var header in ForwardedHeaders)
        {
            if (context.Request.Headers.TryGetValue(header, out var value))
            {
                request.Headers.TryAddWithoutValidation(header, value.ToArray());
            }
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted);
        timeout.CancelAfter(ConnectTimeout);

        HttpResponseMessage response;
        try
        {
            response = invoker is null
                ? await httpClientFactory.CreateClient(HttpClientName).SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token)
                : await invoker.SendAsync(request, timeout.Token);
        }
        catch (Exception exception) when (exception is HttpRequestException or OperationCanceledException)
        {
            context.Response.StatusCode = StatusCodes.Status502BadGateway;
            return;
        }

        using (response)
        {
            if ((int)response.StatusCode is >= 300 and < 400)
            {
                context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
                return;
            }

            byte[] body;
            try
            {
                body = await ReadLimitedAsync(response.Content, MaxMessageBytes, timeout.Token);
            }
            catch (Exception exception) when (exception is InvalidDataException or HttpRequestException or OperationCanceledException)
            {
                context.Response.StatusCode = StatusCodes.Status502BadGateway;
                return;
            }

            context.Response.StatusCode = (int)response.StatusCode;
            context.Response.ContentType = "text/plain; charset=utf-8";
            context.Response.Headers.CacheControl = "no-store";
            await context.Response.Body.WriteAsync(body, context.RequestAborted);
        }
    }

    private static async Task<byte[]> ReadLimitedAsync(HttpContent content, int limit, CancellationToken cancellationToken)
    {
        if (content.Headers.ContentLength > limit)
        {
            throw new InvalidDataException("Upstream response is too large");
        }

        await using var stream = await content.ReadAsStreamAsync(cancellationToken);
        using var buffer = new MemoryStream();
        var chunk = ArrayPool<byte>.Shared.Rent(16 * 1024);
        try
        {
            int read;
            while ((read = await stream.ReadAsync(chunk, cancellationToken)) > 0)
            {
                if (buffer.Length + read > limit)
                {
                    throw new InvalidDataException("Upstream response is too large");
                }

                buffer.Write(chunk, 0, read);
            }
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(chunk);
        }

        return buffer.ToArray();
    }

    private async Task ProxyWebSocketAsync(HttpContext context, Uri target, string? bearer, HttpMessageInvoker? invoker = null)
    {
        using var upstream = new ClientWebSocket();
        if (bearer is not null)
        {
            upstream.Options.SetRequestHeader("Authorization", $"Bearer {bearer}");
        }

        upstream.Options.CollectHttpResponseDetails = true;
        upstream.Options.KeepAliveInterval = KeepAliveInterval;
        upstream.Options.KeepAliveTimeout = KeepAliveTimeout;
        if (context.Request.Headers.UserAgent.Count > 0)
        {
            upstream.Options.SetRequestHeader("User-Agent", context.Request.Headers.UserAgent.ToString());
        }

        var socketUri = new UriBuilder(target) { Scheme = target.Scheme == Uri.UriSchemeHttps ? "wss" : "ws" }.Uri;

        using (var timeout = CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted))
        {
            timeout.CancelAfter(ConnectTimeout);
            try
            {
                if (invoker is null)
                {
                    await upstream.ConnectAsync(socketUri, timeout.Token);
                }
                else
                {
                    await upstream.ConnectAsync(socketUri, invoker, timeout.Token);
                }
            }
            catch (Exception exception) when (exception is WebSocketException or OperationCanceledException or HttpRequestException)
            {
                var status = (int)upstream.HttpStatusCode;
                context.Response.StatusCode = status is >= 400 and < 500 ? status : StatusCodes.Status502BadGateway;
                return;
            }
        }

        using var downstream = await context.WebSockets.AcceptWebSocketAsync(new WebSocketAcceptContext { KeepAliveInterval = KeepAliveInterval, KeepAliveTimeout = KeepAliveTimeout });
        using var lifetime = CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted);

        var toUpstream = PumpAsync(downstream, upstream, lifetime.Token);
        var toDownstream = PumpAsync(upstream, downstream, lifetime.Token);

        var finished = await Task.WhenAny(toUpstream, toDownstream);
        if (finished.IsCompletedSuccessfully)
        {
            await Task.WhenAny(finished == toUpstream ? toDownstream : toUpstream, Task.Delay(CloseTimeout));
        }

        await lifetime.CancelAsync();

        Abort(upstream);
        Abort(downstream);
        await Task.WhenAll(Swallow(toUpstream), Swallow(toDownstream));
    }

    private static async Task PumpAsync(WebSocket source, WebSocket destination, CancellationToken cancellationToken)
    {
        var buffer = ArrayPool<byte>.Shared.Rent(64 * 1024);
        try
        {
            var messageBytes = 0;
            while (!cancellationToken.IsCancellationRequested)
            {
                var result = await source.ReceiveAsync(buffer.AsMemory(), cancellationToken);

                if (result.MessageType == WebSocketMessageType.Close)
                {
                    if (destination.State is WebSocketState.Open or WebSocketState.CloseReceived)
                    {
                        await destination.CloseOutputAsync(source.CloseStatus ?? WebSocketCloseStatus.NormalClosure, source.CloseStatusDescription, cancellationToken);
                    }

                    return;
                }

                messageBytes += result.Count;
                if (messageBytes > MaxMessageBytes)
                {
                    await CloseQuietlyAsync(source, WebSocketCloseStatus.MessageTooBig);
                    await CloseQuietlyAsync(destination, WebSocketCloseStatus.MessageTooBig);
                    return;
                }

                await destination.SendAsync(buffer.AsMemory(0, result.Count), result.MessageType, result.EndOfMessage, cancellationToken);
                if (result.EndOfMessage)
                {
                    messageBytes = 0;
                }
            }
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(buffer);
        }
    }

    private static async Task CloseQuietlyAsync(WebSocket socket, WebSocketCloseStatus status)
    {
        if (socket.State is not (WebSocketState.Open or WebSocketState.CloseReceived))
        {
            return;
        }

        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(2));
        try
        {
            await socket.CloseOutputAsync(status, null, timeout.Token);
        }
        catch (Exception exception) when (exception is WebSocketException or OperationCanceledException)
        {
            socket.Abort();
        }
    }

    private static void Abort(WebSocket socket)
    {
        if (socket.State is not (WebSocketState.Closed or WebSocketState.Aborted))
        {
            socket.Abort();
        }
    }

    private static async Task Swallow(Task task)
    {
        try
        {
            await task;
        }
        catch (Exception exception) when (exception is WebSocketException or OperationCanceledException or ObjectDisposedException)
        {
        }
    }
}
