const accountTarget = (account) => {
  const domain = account?.acct?.split('@')[1];
  return domain && account.id ? [domain, account.id] : undefined;
};

const createDomainFilter = (req, payload) => {
  const targets = [accountTarget(payload.account), accountTarget(payload.reblog?.account)].filter(Boolean);
  if (targets.length === 0) return undefined;

  return {
    query(client) {
      const domains = targets.map(([domain]) => domain);
      const accountIds = targets.map(([, accountId]) => accountId);

      return client.query(
        `SELECT 1 FROM account_domain_blocks WHERE account_id = $1 AND domain = ANY($2::text[])
         UNION
         SELECT 1
         FROM account_domain_mutes
         INNER JOIN unnest($2::text[], $3::bigint[]) AS targets(domain, account_id)
           ON targets.domain = account_domain_mutes.domain
         WHERE account_domain_mutes.account_id = $1
           AND NOT EXISTS (SELECT 1 FROM follows WHERE account_id = $1 AND target_account_id = targets.account_id)`,
        [req.accountId, domains, accountIds]
      );
    },
  };
};

export { createDomainFilter };
