using System.Diagnostics.CodeAnalysis;
using System.Text.Json;

namespace VoiceSignal;

public sealed record TokenClaims(string Identity, string Room)
{
    private const int MaxIdentityLength = 2048;
    private const int MaxRoomLength = 512;

    public static bool TryParse(string token, [NotNullWhen(true)] out TokenClaims? claims)
    {
        claims = null;

        var parts = token.Split('.');
        if (parts.Length != 3)
        {
            return false;
        }

        try
        {
            using var document = JsonDocument.Parse(Base64Url.Decode(parts[1]));
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object
                || !root.TryGetProperty("sub", out var subject) || subject.ValueKind != JsonValueKind.String
                || !root.TryGetProperty("video", out var video) || video.ValueKind != JsonValueKind.Object
                || !video.TryGetProperty("room", out var room) || room.ValueKind != JsonValueKind.String)
            {
                return false;
            }

            var identity = subject.GetString()!;
            var roomName = room.GetString()!;
            if (identity.Length is < 1 or > MaxIdentityLength || roomName.Length is < 1 or > MaxRoomLength)
            {
                return false;
            }

            claims = new TokenClaims(identity, roomName);
            return true;
        }
        catch (Exception exception) when (exception is FormatException or JsonException)
        {
            return false;
        }
    }
}
