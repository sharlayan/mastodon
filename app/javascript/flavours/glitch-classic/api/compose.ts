import { apiRequestPut } from 'flavours/glitch-classic/api';
import type { ApiMediaAttachmentJSON } from 'flavours/glitch-classic/api_types/media_attachments';

export const apiUpdateMedia = (
  id: string,
  params?: { description?: string; focus?: string },
) => apiRequestPut<ApiMediaAttachmentJSON>(`v1/media/${id}`, params);
