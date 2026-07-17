const accountTarget = (account) => {
  const domain = account?.acct?.split('@')[1];
  return domain && account.id ? [domain, account.id] : undefined;
};

const createDomainFilter = (req, payload) => {
  const targets = [accountTarget(payload.account), accountTarget(payload.reblog?.account)].filter(Boolean);

  return {
    async query(client) {
      const domains = targets.map(([domain]) => domain);
      const accountIds = targets.map(([, accountId]) => accountId);
      const loadFilters = !Object.hasOwn(payload, 'filtered') && !req.cachedFilters;
      const domainQuery = targets.length > 0 ? client.query(
        `SELECT 1 FROM account_domain_blocks WHERE account_id = $1 AND domain = ANY($2::text[])
         UNION
         SELECT 1
         FROM account_domain_mutes
         INNER JOIN unnest($2::text[], $3::bigint[]) AS targets(domain, account_id)
           ON targets.domain = account_domain_mutes.domain
         WHERE account_domain_mutes.account_id = $1
           AND NOT EXISTS (SELECT 1 FROM follows WHERE account_id = $1 AND target_account_id = targets.account_id)`,
        [req.accountId, domains, accountIds]
      ) : Promise.resolve({ rows: [] });
      const filterQuery = loadFilters ? client.query(
        'SELECT filter.id AS id, filter.phrase AS title, filter.context AS context, filter.expires_at AS expires_at, filter.action AS filter_action, keyword.keyword AS keyword, keyword.whole_word AS whole_word FROM custom_filter_keywords keyword JOIN custom_filters filter ON keyword.custom_filter_id = filter.id WHERE filter.account_id = $1 AND (filter.expires_at IS NULL OR filter.expires_at > NOW())',
        [req.accountId]
      ) : Promise.resolve({ rows: [] });
      const [domainResult, filterResult] = await Promise.all([domainQuery, filterQuery]);

      return Object.assign(domainResult, {
        blocked: domainResult.rows.length > 0,
        filterRows: filterResult.rows,
      });
    },
  };
};

export { createDomainFilter };
