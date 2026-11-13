using System.Net;
using System.Net.Sockets;

namespace VoiceSignal;

public static class PublicAddressConnector
{
    private static readonly IPNetwork[] NonPublicNetworks =
    [
        .. new[]
        {
            "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12",
            "192.0.0.0/24", "192.0.2.0/24", "192.88.99.0/24", "192.168.0.0/16", "198.18.0.0/15",
            "198.51.100.0/24", "203.0.113.0/24", "224.0.0.0/4", "240.0.0.0/4",
            "::/96", "64:ff9b::/96", "64:ff9b:1::/48", "100::/64", "2001::/32", "2001:10::/28", "2001:20::/28",
            "2001:db8::/32", "2002::/16", "3fff::/20", "fc00::/7", "fe80::/10", "fec0::/10", "ff00::/8",
        }.Select(network => IPNetwork.Parse(network)),
    ];

    public static SocketsHttpHandler CreateHandler(bool allowPrivate) => new()
    {
        AllowAutoRedirect = false,
        UseCookies = false,
        UseProxy = false,
        ConnectTimeout = TimeSpan.FromSeconds(5),
        ConnectCallback = (context, cancellationToken) => ConnectAsync(context.DnsEndPoint, allowPrivate, cancellationToken),
    };

    public static async ValueTask<Stream> ConnectAsync(DnsEndPoint endPoint, bool allowPrivate, CancellationToken cancellationToken)
    {
        var addresses = await Dns.GetHostAddressesAsync(endPoint.Host, cancellationToken);
        var allowed = addresses.Where(address => allowPrivate || IsPublic(address)).ToArray();
        if (allowed.Length == 0)
        {
            throw new HttpRequestException($"{endPoint.Host} does not resolve to a public address");
        }

        var socket = new Socket(SocketType.Stream, ProtocolType.Tcp) { NoDelay = true };
        try
        {
            await socket.ConnectAsync(allowed, endPoint.Port, cancellationToken);
            return new NetworkStream(socket, ownsSocket: true);
        }
        catch
        {
            socket.Dispose();
            throw;
        }
    }

    public static bool IsPublic(IPAddress address)
    {
        if (address.IsIPv4MappedToIPv6)
        {
            address = address.MapToIPv4();
        }

        return !NonPublicNetworks.Any(network => network.Contains(address));
    }
}
