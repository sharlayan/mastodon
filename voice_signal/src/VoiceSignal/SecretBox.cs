using System.Security.Cryptography;
using System.Text;

namespace VoiceSignal;

public static class SecretBox
{
    private const string Version = "v1";
    private const string Context = "sharlayan voice relay provider secret v1";
    private const int IvLength = 12;
    private const int TagLength = 16;

    public static string Decrypt(string payload, string secretKeyBase)
    {
        var separator = payload.IndexOf(':');
        if (separator < 0 || payload[..separator] != Version)
        {
            throw new CryptographicException("Unsupported secret format");
        }

        var raw = Convert.FromBase64String(payload[(separator + 1)..]);
        if (raw.Length <= IvLength + TagLength)
        {
            throw new CryptographicException("Secret payload is too short");
        }

        var key = HMACSHA256.HashData(Encoding.UTF8.GetBytes(secretKeyBase), Encoding.UTF8.GetBytes(Context));
        var plaintext = new byte[raw.Length - IvLength - TagLength];

        using var aes = new AesGcm(key, TagLength);
        aes.Decrypt(raw.AsSpan(0, IvLength), raw.AsSpan(IvLength + TagLength), raw.AsSpan(IvLength, TagLength), plaintext);

        return Encoding.UTF8.GetString(plaintext);
    }
}
