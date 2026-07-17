import { AuthenticationError, RequestError } from '../errors.js';

const CHANNEL_NAME = 'antenna';

const channelNameFromPath = (path) => path === '/api/v1/streaming/antenna' ? CHANNEL_NAME : undefined;

const authorizeChannel = async (pgPool, req, name, params) => {
  if (name !== CHANNEL_NAME) return undefined;
  if (!params.antenna) throw new RequestError('Missing antenna id parameter');

  let result;
  try {
    result = await pgPool.query(`
      SELECT antennas.id, antennas.account_id
      FROM antennas
      LEFT JOIN settings ON settings.var = 'antenna_enabled'
      WHERE antennas.id = $1
        AND antennas.account_id = $2
        AND COALESCE(settings.value, '--- true\n') = '--- true\n'
      LIMIT 1
    `, [params.antenna, req.accountId]);
  } catch {
    throw new AuthenticationError('Not authorized to stream this antenna');
  }

  if (result.rows.length === 0) {
    throw new AuthenticationError('Not authorized to stream this antenna');
  }

  return {
    channelIds: [`timeline:antenna:${params.antenna}`],
    options: { needsFiltering: false, allowLocalOnly: true },
  };
};

const streamName = (channelName, params) => channelName === CHANNEL_NAME && params.antenna ? [channelName, params.antenna] : undefined;

export { CHANNEL_NAME, authorizeChannel, channelNameFromPath, streamName };
