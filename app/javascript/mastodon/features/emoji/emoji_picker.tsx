import type { EmojiProps, PickerProps } from 'emoji-mart';

import { assetHost } from 'mastodon/utils/config';

import { NimbleEmoji, NimblePicker } from '../emoji_mart_lazyload';

import { EMOJI_MODE_NATIVE } from './constants';
import EmojiData from './emoji_data.json';
import { useEmojiAppState } from './mode';

const backgroundImageFnDefault = () => `${assetHost}/emoji/sheet_16_0.png`;

const Emoji = ({
  set = 'twitter',
  sheetSize = 32,
  sheetColumns = 62,
  sheetRows = 62,
  backgroundImageFn = backgroundImageFnDefault,
  ...props
}: EmojiProps) => {
  const { mode } = useEmojiAppState();
  return (
    <NimbleEmoji
      data={EmojiData}
      set={set}
      sheetSize={sheetSize}
      sheetColumns={sheetColumns}
      sheetRows={sheetRows}
      native={mode === EMOJI_MODE_NATIVE}
      backgroundImageFn={backgroundImageFn}
      {...props}
    />
  );
};

const Picker = ({
  set = 'twitter',
  sheetSize = 32,
  sheetColumns = 62,
  sheetRows = 62,
  backgroundImageFn = backgroundImageFnDefault,
  ...props
}: PickerProps) => {
  const { mode } = useEmojiAppState();
  return (
    <NimblePicker
      data={EmojiData}
      set={set}
      sheetSize={sheetSize}
      sheetColumns={sheetColumns}
      sheetRows={sheetRows}
      backgroundImageFn={backgroundImageFn}
      native={mode === EMOJI_MODE_NATIVE}
      {...props}
    />
  );
};

export { Picker, Emoji };
