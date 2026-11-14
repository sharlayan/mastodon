import api, { getLinks } from 'flavours/glitch-classic/api';
import type { ApiDomainMuteJSON } from 'flavours/glitch-classic/api_types/domain_mute';

export const apiGetDomainMutes = async (url?: string) => {
  const response = await api().request<ApiDomainMuteJSON[]>({
    method: 'GET',
    url: url ?? '/api/v1/domain_mutes',
  });

  return {
    domains: response.data,
    links: getLinks(response),
  };
};
