using Microsoft.Extensions.Caching.Memory;
using Npgsql;

namespace VoiceSignal;

public sealed record Upstream(string Origin, string RemoteId, string SecretCiphertext);

public interface IAllocationResolver
{
    Task<Upstream?> ResolveAsync(TokenHint hint, CancellationToken cancellationToken);

    Task<string?> ResolveRemoteOriginAsync(TokenClaims claims, CancellationToken cancellationToken);
}

public sealed class DatabaseAllocationResolver(NpgsqlDataSource dataSource, IMemoryCache cache) : IAllocationResolver
{
    private const string Query = """
        SELECT p.origin, a.remote_id, p.secret_ciphertext
        FROM voice_call_allocations a
        JOIN voice_relay_providers p ON p.id = a.voice_relay_provider_id
        WHERE a.remote_id = $1 AND a.generation = $2 AND a.state = 'active'
        LIMIT 2
        """;

    private const string RemoteQuery = """
        SELECT origin
        FROM voice_call_remote_sessions
        WHERE identity = $1 AND room_name = $2 AND expires_at > now()
        LIMIT 1
        """;

    private static readonly TimeSpan PositiveLifetime = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan NegativeLifetime = TimeSpan.FromSeconds(5);

    public async Task<Upstream?> ResolveAsync(TokenHint hint, CancellationToken cancellationToken)
    {
        var key = (hint.AllocationId, hint.Generation);
        if (cache.TryGetValue(key, out Upstream? cached))
        {
            return cached;
        }

        await using var command = dataSource.CreateCommand(Query);
        command.Parameters.AddWithValue(hint.AllocationId);
        command.Parameters.AddWithValue(hint.Generation);

        var rows = new List<Upstream>(2);
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                rows.Add(new Upstream(reader.GetString(0), reader.GetString(1), reader.GetString(2)));
            }
        }

        var result = rows.Count == 1 ? rows[0] : null;
        cache.Set(key, result, new MemoryCacheEntryOptions { AbsoluteExpirationRelativeToNow = result is null ? NegativeLifetime : PositiveLifetime, Size = 1 });
        return result;
    }

    public async Task<string?> ResolveRemoteOriginAsync(TokenClaims claims, CancellationToken cancellationToken)
    {
        var key = ("remote", claims.Identity, claims.Room);
        if (cache.TryGetValue(key, out string? cached))
        {
            return cached;
        }

        await using var command = dataSource.CreateCommand(RemoteQuery);
        command.Parameters.AddWithValue(claims.Identity);
        command.Parameters.AddWithValue(claims.Room);
        var result = await command.ExecuteScalarAsync(cancellationToken) as string;

        cache.Set(key, result, new MemoryCacheEntryOptions { AbsoluteExpirationRelativeToNow = result is null ? NegativeLifetime : PositiveLifetime, Size = 1 });
        return result;
    }
}
