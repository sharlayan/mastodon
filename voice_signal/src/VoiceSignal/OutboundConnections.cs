using System.Net;

namespace VoiceSignal;

public static class OutboundConnections
{
    private static readonly TimeSpan ConnectTimeout = TimeSpan.FromSeconds(5);

    public static SocketsHttpHandler CreateRelayHandler(SignalOptions options) => new()
    {
        AllowAutoRedirect = false,
        UseCookies = false,
        ConnectTimeout = ConnectTimeout,
        UseProxy = options.OutboundProxy is not null,
        Proxy = options.OutboundProxy is null ? null : CreateProxy(options.OutboundProxy),
    };

    public static SocketsHttpHandler CreateRemoteHandler(SignalOptions options) =>
        options.OutboundProxy is null ? PublicAddressConnector.CreateHandler(options.AllowInsecureUpstream) : CreateRelayHandler(options);

    public static WebProxy CreateProxy(Uri uri)
    {
        var proxy = new WebProxy(new UriBuilder(uri) { UserName = string.Empty, Password = string.Empty, Path = string.Empty, Query = string.Empty, Fragment = string.Empty }.Uri)
        {
            BypassProxyOnLocal = false,
        };

        if (uri.UserInfo.Length > 0)
        {
            var parts = uri.UserInfo.Split(':', 2);
            proxy.Credentials = new NetworkCredential(Uri.UnescapeDataString(parts[0]), parts.Length > 1 ? Uri.UnescapeDataString(parts[1]) : string.Empty);
        }

        return proxy;
    }
}
