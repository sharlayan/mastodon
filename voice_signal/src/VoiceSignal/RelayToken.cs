using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace VoiceSignal;

public static class RelayToken
{
    public const string TokenType = "voice-relay-client+jwt";
    public const int TimeToLiveSeconds = 60;
    public const int MinimumSecretLength = 32;

    public static string Create(string secret, string issuer, string audience, DateTimeOffset now)
    {
        if (secret.Length < MinimumSecretLength)
        {
            throw new CryptographicException("Relay secret is too short");
        }

        var issuedAt = now.ToUnixTimeSeconds();
        var header = JsonSerializer.SerializeToUtf8Bytes(new Dictionary<string, object> { ["alg"] = "HS256", ["typ"] = TokenType });
        var payload = JsonSerializer.SerializeToUtf8Bytes(new Dictionary<string, object>
        {
            ["iss"] = issuer,
            ["aud"] = audience,
            ["iat"] = issuedAt,
            ["exp"] = issuedAt + TimeToLiveSeconds,
        });

        var signingInput = $"{Base64Url.Encode(header)}.{Base64Url.Encode(payload)}";
        var signature = HMACSHA256.HashData(Encoding.UTF8.GetBytes(secret), Encoding.ASCII.GetBytes(signingInput));

        return $"{signingInput}.{Base64Url.Encode(signature)}";
    }
}

public static class Base64Url
{
    public static string Encode(ReadOnlySpan<byte> bytes) => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    public static byte[] Decode(string value)
    {
        var padded = value.Replace('-', '+').Replace('_', '/');
        padded += (padded.Length % 4) switch
        {
            2 => "==",
            3 => "=",
            0 => string.Empty,
            _ => throw new FormatException("Invalid base64url length"),
        };

        return Convert.FromBase64String(padded);
    }
}
