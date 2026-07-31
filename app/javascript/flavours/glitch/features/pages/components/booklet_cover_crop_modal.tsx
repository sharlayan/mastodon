import { useCallback, useState } from 'react';
import type { ChangeEventHandler, FC } from 'react';

import { FormattedMessage, useIntl } from 'react-intl';

import type { Area } from 'react-easy-crop';
import Cropper from 'react-easy-crop';

import { Button } from 'flavours/glitch/components/button';
import { RangeInputField } from 'flavours/glitch/components/form_fields/range_input_field';
import accountEditClasses from 'flavours/glitch/features/account_edit/modals/styles.module.scss';
import { DialogModal } from 'flavours/glitch/features/ui/components/dialog_modal';
import type { DialogModalProps } from 'flavours/glitch/features/ui/components/dialog_modal';

import 'react-easy-crop/react-easy-crop.css';

export const BookletCoverCropModal: FC<
  DialogModalProps & {
    src: string;
    title: string;
    onComplete: (blob: Blob) => Promise<void>;
    onError: (error: unknown) => void;
  }
> = ({ onClose, src, title, onComplete, onError }) => {
  const intl = useIntl();
  const [crop, setCrop] = useState({ x: 0, y: 0 });
  const [croppedArea, setCroppedArea] = useState<Area | null>(null);
  const [zoom, setZoom] = useState(1);
  const [processing, setProcessing] = useState(false);

  const handleZoomChange: ChangeEventHandler<HTMLInputElement> = useCallback(
    (event) => {
      setZoom(event.currentTarget.valueAsNumber);
    },
    [],
  );

  const handleCropComplete = useCallback((_: Area, area: Area) => {
    setCroppedArea(area);
  }, []);

  const handleDone = useCallback(() => {
    if (!croppedArea || processing) return;

    setProcessing(true);
    void cropImage(src, croppedArea)
      .then(onComplete)
      .then(onClose)
      .catch((error: unknown) => {
        setProcessing(false);
        onError(error);
      });
  }, [croppedArea, onClose, onComplete, onError, processing, src]);

  return (
    <DialogModal
      title={title}
      onClose={onClose}
      wrapperClassName={accountEditClasses.uploadWrapper}
      noCancelButton
    >
      <div className={accountEditClasses.cropContainer}>
        <Cropper
          image={src}
          crop={crop}
          zoom={zoom}
          aspect={3 / 4}
          onCropChange={setCrop}
          onCropComplete={handleCropComplete}
          disableAutomaticStylesInjection
        />
      </div>
      <div className={accountEditClasses.cropActions}>
        <RangeInputField
          label={intl.formatMessage({
            id: 'account_edit.upload_modal.step_crop.zoom',
            defaultMessage: 'Zoom',
          })}
          min={1}
          max={3}
          step={0.1}
          value={zoom}
          onChange={handleZoomChange}
          wrapperClassName={accountEditClasses.zoomControl}
          inputPlacement='inline-end'
        />
        <Button onClick={onClose} secondary disabled={processing}>
          <FormattedMessage
            id='confirmation_modal.cancel'
            defaultMessage='Cancel'
          />
        </Button>
        <Button onClick={handleDone} disabled={!croppedArea || processing}>
          <FormattedMessage
            id='account_edit.upload_modal.done'
            defaultMessage='Done'
          />
        </Button>
      </div>
    </DialogModal>
  );
};

async function cropImage(src: string, crop: Area): Promise<Blob> {
  const image = await loadImage(src);
  const scale = Math.min(1, 600 / crop.width, 800 / crop.height);
  const canvas = new OffscreenCanvas(
    Math.round(crop.width * scale),
    Math.round(crop.height * scale),
  );
  const context = canvas.getContext('2d');
  if (!context) throw new Error('Failed to get canvas context');

  context.imageSmoothingQuality = 'high';
  context.drawImage(
    image,
    crop.x,
    crop.y,
    crop.width,
    crop.height,
    0,
    0,
    canvas.width,
    canvas.height,
  );

  return canvas.convertToBlob();
}

function loadImage(src: string) {
  return new Promise<HTMLImageElement>((resolve, reject) => {
    const image = new Image();
    image.addEventListener('load', () => {
      resolve(image);
    });
    image.addEventListener('error', () => {
      reject(new Error('Failed to load image'));
    });
    image.src = src;
  });
}
