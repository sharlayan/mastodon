using System.Diagnostics.CodeAnalysis;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace VoiceSignal;

public sealed partial record TokenHint(string AllocationId, string Generation)
{
    [GeneratedRegex("^[a-zA-Z0-9-]{1,128}$")]
    private static partial Regex AllocationIdPattern();

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
            if (!claims.RootElement.TryGetProperty("metadata", out var metadataElement) || metadataElement.ValueKind != JsonValueKind.String)
            {
                return false;
            }

            using var metadata = JsonDocument.Parse(metadataElement.GetString()!);
            var root = metadata.RootElement;
            if (root.ValueKind != JsonValueKind.Object
                || !root.TryGetProperty("allocationId", out var allocationId) || allocationId.ValueKind != JsonValueKind.String
                || !root.TryGetProperty("generation", out var generation) || generation.ValueKind != JsonValueKind.String)
            {
                return false;
            }

            var allocation = allocationId.GetString()!;
            var generationValue = generation.GetString()!;
            if (!AllocationIdPattern().IsMatch(allocation) || generationValue.Length is < 1 or > 128)
            {
                return false;
            }

            hint = new TokenHint(allocation, generationValue);
            return true;
        }
        catch (Exception exception) when (exception is FormatException or JsonException)
        {
            return false;
        }
    }
}
