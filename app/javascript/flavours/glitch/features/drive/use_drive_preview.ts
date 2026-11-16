import { useCallback } from 'react';

import { fromJS } from 'immutable';

import { openModal } from 'flavours/glitch/actions/modal';
import type { ApiDriveFileJSON } from 'flavours/glitch/api_types/drive';
import { useAppDispatch } from 'flavours/glitch/store';

const PREVIEWABLE_TYPES = ['image', 'gifv', 'video'];

export const useDrivePreview = (files: ApiDriveFileJSON[]) => {
  const dispatch = useAppDispatch();

  return useCallback(
    (file: ApiDriveFileJSON) => {
      if (file.type === 'audio') {
        dispatch(
          openModal({
            modalType: 'AUDIO',
            modalProps: {
              media: fromJS(file),
              options: { autoPlay: true },
            },
          }),
        );

        return;
      }

      if (!PREVIEWABLE_TYPES.includes(file.type)) {
        window.open(file.url, '_blank', 'noopener,noreferrer');

        return;
      }

      const media = files.filter((candidate) =>
        PREVIEWABLE_TYPES.includes(candidate.type),
      );
      const index = media.findIndex((candidate) => candidate.id === file.id);

      dispatch(
        openModal({
          modalType: 'MEDIA',
          modalProps: { media: fromJS(media), index: index < 0 ? 0 : index },
        }),
      );
    },
    [dispatch, files],
  );
};
