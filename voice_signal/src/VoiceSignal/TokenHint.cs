using System.Diagnostics.CodeAnalysis;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace VoiceSignal;

public sealed partial record TokenHint(string AllocationId, string Generation, long UserId)
{
    [GeneratedRegex("^[a-zA-Z0-9-]{1,128}$")]
    private static partial Regex AllocationIdPattern();

    [GeneratedRegex("^[1-9][0-9]{0,18}$")]
    private static partial Regex UserIdPattern();

    public static bool TryParse(string token, [NotNullWhen(true)] out TokenHint? hint)
    {
        hint = null;

        var parts = token.Split('.');
        if (parts.Length != 3)
        {
            return false;
        }

        try
        {
            using var claims = JsonDocument.Parse(Base64Url.Decode(parts[1]));
            if (claims.RootElement.ValueKind != JsonValueKind.Object
                || !claims.RootElement.TryGetProperty("metadata", out var metadataElement) || metadataElement.ValueKind != JsonValueKind.String)
            {
                return false;
            }

            using var metadata = JsonDocument.Parse(metadataElement.GetString()!);
            var root = metadata.RootElement;
            if (root.ValueKind != JsonValueKind.Object
                || !root.TryGetProperty("allocationId", out var allocationId) || allocationId.ValueKind != JsonValueKind.String
                || !root.TryGetProperty("generation", out var generation) || generation.ValueKind != JsonValueKind.String
                || !root.TryGetProperty("userId", out var userIdElement) || userIdElement.ValueKind != JsonValueKind.String)
            {
                return false;
            }

            var allocation = allocationId.GetString()!;
            var generationValue = generation.GetString()!;
            if (!AllocationIdPattern().IsMatch(allocation) || generationValue.Length is < 1 or > 128
                || !UserIdPattern().IsMatch(userIdElement.GetString()!) || !long.TryParse(userIdElement.GetString(), out var userId))
            {
                return false;
            }

            hint = new TokenHint(allocation, generationValue, userId);
            return true;
        }
        catch (Exception exception) when (exception is FormatException or JsonException)
        {
            return false;
        }
    }
}
