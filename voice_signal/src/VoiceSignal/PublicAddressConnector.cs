using System.Net;
using System.Net.Sockets;

namespace VoiceSignal;

public static class PublicAddressConnector
{
    public static SocketsHttpHandler CreateHandler(bool allowPrivate) => new()
    {
        AllowAutoRedirect = false,
        UseCookies = false,
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

        if (IPAddress.IsLoopback(address) || address.Equals(IPAddress.Any) || address.Equals(IPAddress.IPv6Any) || address.Equals(IPAddress.Broadcast))
        {
            return false;
        }

        if (address.AddressFamily == AddressFamily.InterNetworkV6)
        {
            return !(address.IsIPv6LinkLocal || address.IsIPv6SiteLocal || address.IsIPv6Multicast || address.IsIPv6UniqueLocal || address.IsIPv6Teredo);
        }

        var bytes = address.GetAddressBytes();
        return bytes[0] switch
        {
            0 or 10 or 127 => false,
            100 => bytes[1] is < 64 or > 127,
            169 => bytes[1] != 254,
            172 => bytes[1] is < 16 or > 31,
            192 => !(bytes[1] == 168 || (bytes[1] == 0 && bytes[2] is 0 or 2)),
            198 => bytes[1] is not (18 or 19),
            >= 224 => false,
            _ => true,
        };
    }
}
