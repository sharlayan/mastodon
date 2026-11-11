using Microsoft.Extensions.Caching.Memory;
using Npgsql;

namespace VoiceSignal;

public sealed record Upstream(string Origin, string RemoteId, string SecretCiphertext);

public interface IAllocationResolver
{
    Task<Upstream?> ResolveAsync(TokenHint hint, CancellationToken cancellationToken);

    Task<bool> IsAdmittedAsync(TokenHint hint, CancellationToken cancellationToken);

    Task<string?> ResolveRemoteOriginAsync(long sessionId, TokenClaims claims, CancellationToken cancellationToken);
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

    private const string AdmissionQuery = """
        SELECT EXISTS (
            SELECT 1
            FROM voice_call_allocations a
            JOIN chat_conversations c ON c.id = a.chat_conversation_id
            JOIN chat_memberships m ON m.chat_conversation_id = a.chat_conversation_id AND m.account_id = $3
            JOIN accounts acc ON acc.id = m.account_id
            LEFT JOIN users u ON u.account_id = acc.id
            WHERE a.remote_id = $1 AND a.generation = $2 AND a.state = 'active'
              AND c.archived_at IS NULL
              AND acc.suspended_at IS NULL
              AND (acc.domain IS NOT NULL OR (u.id IS NOT NULL AND NOT u.disabled))
        )
        """;

    private const string RemoteQuery = """
        SELECT origin
        FROM voice_call_remote_sessions
        WHERE id = $1 AND identity = $2 AND room_name = $3 AND expires_at > now()
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

    public async Task<bool> IsAdmittedAsync(TokenHint hint, CancellationToken cancellationToken)
    {
        await using var command = dataSource.CreateCommand(AdmissionQuery);
        command.Parameters.AddWithValue(hint.AllocationId);
        command.Parameters.AddWithValue(hint.Generation);
        command.Parameters.AddWithValue(hint.UserId);
        return await command.ExecuteScalarAsync(cancellationToken) is true;
    }

    public async Task<string?> ResolveRemoteOriginAsync(long sessionId, TokenClaims claims, CancellationToken cancellationToken)
    {
        var key = ("remote", sessionId, claims.Identity, claims.Room);
        if (cache.TryGetValue(key, out string? cached))
        {
            return cached;
        }

        await using var command = dataSource.CreateCommand(RemoteQuery);
        command.Parameters.AddWithValue(sessionId);
        command.Parameters.AddWithValue(claims.Identity);
        command.Parameters.AddWithValue(claims.Room);
        var result = await command.ExecuteScalarAsync(cancellationToken) as string;

        cache.Set(key, result, new MemoryCacheEntryOptions { AbsoluteExpirationRelativeToNow = result is null ? NegativeLifetime : PositiveLifetime, Size = 1 });
        return result;
    }
}
