using System.Diagnostics.CodeAnalysis;
using System.Text.Json;

namespace VoiceSignal;

public sealed record TokenClaims(string Identity, string Room, bool CanPublishScreenShare = true)
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

            if (!TryScreenSharePermission(video, out var canPublishScreenShare))
            {
                return false;
            }

            claims = new TokenClaims(identity, roomName, canPublishScreenShare);
            return true;
        }
        catch (Exception exception) when (exception is FormatException or JsonException)
        {
            return false;
        }
    }

    private static bool TryScreenSharePermission(JsonElement video, out bool allowed)
    {
        allowed = false;
        var canPublish = true;
        if (video.TryGetProperty("canPublish", out var publish) && publish.ValueKind != JsonValueKind.Null)
        {
            if (publish.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            {
                return false;
            }

            canPublish = publish.GetBoolean();
        }

        if (!video.TryGetProperty("canPublishSources", out var sources) || sources.ValueKind == JsonValueKind.Null)
        {
            allowed = canPublish;
            return true;
        }

        if (sources.ValueKind != JsonValueKind.Array || sources.EnumerateArray().Any(source => source.ValueKind != JsonValueKind.String))
        {
            return false;
        }

        allowed = canPublish && (sources.GetArrayLength() == 0
            || sources.EnumerateArray().Any(source => source.GetString() is "screen_share" or "screen_share_audio"));
        return true;
    }
}
