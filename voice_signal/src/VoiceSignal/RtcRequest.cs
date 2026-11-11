using System.Diagnostics.CodeAnalysis;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.WebUtilities;

namespace VoiceSignal;

public sealed partial record RtcRequest(string Suffix, string AccessToken)
{
    public const int MaxTokenLength = 16_384;

    [GeneratedRegex("%(?:2f|5c|25)", RegexOptions.IgnoreCase)]
    private static partial Regex EncodedSeparator();

    public static bool TryParse(string rawTarget, string basePath, [NotNullWhen(true)] out RtcRequest? request)
    {
        request = null;

        var queryStart = rawTarget.IndexOf('?');
        var path = queryStart < 0 ? rawTarget : rawTarget[..queryStart];
        var query = queryStart < 0 ? string.Empty : rawTarget[queryStart..];

        var rtcPath = basePath + "/rtc";
        if (path != rtcPath && !path.StartsWith(rtcPath + "/", StringComparison.Ordinal))
        {
            return false;
        }

        if (path.Contains('\\') || EncodedSeparator().IsMatch(path))
        {
            return false;
        }

        string decoded;
        try
        {
            decoded = Uri.UnescapeDataString(path);
        }
        catch (UriFormatException)
        {
            return false;
        }

        if (decoded.Split('/').Any(segment => segment is "." or ".."))
        {
            return false;
        }

        var tokens = QueryHelpers.ParseQuery(query).TryGetValue("access_token", out var values) ? values : default;
        if (tokens.Count != 1 || string.IsNullOrEmpty(tokens[0]) || tokens[0]!.Length > MaxTokenLength)
        {
            return false;
        }

        request = new RtcRequest(path[basePath.Length..] + query, tokens[0]!);
        return true;
    }
}
