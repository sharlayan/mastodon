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

public sealed class DatabaseAllocationResolver(NpgsqlDataSource dataSource, IMemoryCache cache, bool roleplayMode = false) : IAllocationResolver
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
        SELECT session.origin
        FROM voice_call_remote_sessions session
        JOIN chat_conversations conversation ON conversation.id = session.chat_conversation_id
        JOIN chat_memberships membership ON membership.chat_conversation_id = session.chat_conversation_id AND membership.account_id = session.account_id
        JOIN accounts account ON account.id = session.account_id
        JOIN users ON users.account_id = account.id
        JOIN accounts owner ON owner.id = conversation.owner_account_id
        LEFT JOIN user_roles role ON role.id = users.role_id
        LEFT JOIN user_roles everyone ON everyone.id = -99
        WHERE session.id = $1 AND session.identity = $2 AND session.room_name = $3 AND session.expires_at > now()
          AND conversation.conversation_type = 1 AND conversation.archived_at IS NULL
          AND account.domain IS NULL AND account.suspended_at IS NULL AND account.requested_deletion_at IS NULL AND NOT account.memorial
          AND NOT users.disabled AND users.approved AND users.confirmed_at IS NOT NULL
          AND (NOT COALESCE(role.require_2fa, everyone.require_2fa, FALSE) OR users.otp_required_for_login
               OR EXISTS (SELECT 1 FROM webauthn_credentials WHERE user_id = users.id))
          AND ((COALESCE(role.permissions, 0) & 1) = 1
               OR ((COALESCE(role.extra_permissions, 0) | COALESCE(everyone.extra_permissions, 12)) & 4) = 4)
          AND (NOT $4::boolean OR (
               ((COALESCE(role.permissions, 0) & 1) = 1
                OR ((COALESCE(role.extra_permissions, 0) | COALESCE(everyone.extra_permissions, 12)) & 8) = 8)
               AND COALESCE((SELECT value FROM settings WHERE var = 'voice_call_screen_share_enabled'), E'--- true\n') = E'--- true\n'
          ))
          AND owner.domain IS NOT NULL AND owner.suspended_at IS NULL AND owner.requested_deletion_at IS NULL
          AND COALESCE((SELECT severity FROM domain_blocks
                        WHERE owner.domain = domain OR owner.domain LIKE '%.' || domain
                        ORDER BY char_length(domain) DESC LIMIT 1), 2) <> 1
          AND EXISTS (SELECT 1 FROM settings WHERE var = 'chat_enabled' AND value = E'--- true\n')
          AND EXISTS (SELECT 1 FROM settings WHERE var = 'voice_call_remote_join_enabled' AND value = E'--- true\n')
          AND COALESCE((SELECT value FROM settings WHERE var = 'chat_federation_enabled'), E'--- true\n') = E'--- true\n'
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
        if (roleplayMode)
        {
            return null;
        }

        await using var command = dataSource.CreateCommand(RemoteQuery);
        command.CommandTimeout = 5;
        command.Parameters.AddWithValue(sessionId);
        command.Parameters.AddWithValue(claims.Identity);
        command.Parameters.AddWithValue(claims.Room);
        command.Parameters.AddWithValue(claims.CanPublishScreenShare);
        return await command.ExecuteScalarAsync(cancellationToken) as string;
    }
}
