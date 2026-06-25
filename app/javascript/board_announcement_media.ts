interface BoardAnnouncementMediaJSON {
  id: string;
  type: 'image' | 'file';
  url: string;
  preview_url: string;
  file_name: string;
}

interface MediaLabels {
  add: string;
  copy: string;
  remove: string;
  copied: string;
  uploading: string;
  error: string;
}

function getCSRFToken() {
  return (
    document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')
      ?.content ?? ''
  );
}

function buildMarkdown(media: BoardAnnouncementMediaJSON) {
  if (media.type === 'image') {
    return `![${media.file_name}](${media.url})`;
  }

  return `[${media.file_name}](${media.url})`;
}

async function copyToClipboard(text: string) {
  await navigator.clipboard.writeText(text);
}

function setupBoardAnnouncementMedia(container: HTMLElement) {
  const uploadUrl = container.dataset.uploadUrl ?? '';
  const destroyUrlTemplate = container.dataset.destroyUrl ?? '';
  const fieldName = container.dataset.fieldName ?? '';

  const labels: MediaLabels = {
    add: container.dataset.labelAdd ?? 'Add media',
    copy: container.dataset.labelCopy ?? 'Click to copy markdown',
    remove: container.dataset.labelRemove ?? 'Remove',
    copied: container.dataset.labelCopied ?? 'Copied to clipboard',
    uploading: container.dataset.labelUploading ?? 'Uploading…',
    error: container.dataset.labelError ?? 'Upload failed',
  };

  let existing: BoardAnnouncementMediaJSON[] = [];

  try {
    existing = JSON.parse(
      container.dataset.existing ?? '[]',
    ) as BoardAnnouncementMediaJSON[];
  } catch {
    existing = [];
  }

  const list = document.createElement('div');
  list.className = 'board-announcement-media__list';

  const status = document.createElement('p');
  status.className = 'board-announcement-media__status';
  status.setAttribute('aria-live', 'polite');
  status.hidden = true;

  const fileInput = document.createElement('input');
  fileInput.type = 'file';
  fileInput.accept = 'image/*';
  fileInput.multiple = true;
  fileInput.className = 'board-announcement-media__file';

  const addButton = document.createElement('button');
  addButton.type = 'button';
  addButton.className = 'button button-secondary board-announcement-media__add';
  addButton.textContent = labels.add;
  addButton.addEventListener('click', () => {
    fileInput.click();
  });

  const showStatus = (message: string, isError: boolean) => {
    status.textContent = message;
    status.hidden = false;
    status.classList.toggle('board-announcement-media__status--error', isError);
  };

  const clearStatus = () => {
    status.hidden = true;
    status.textContent = '';
  };

  const removeMedia = (
    media: BoardAnnouncementMediaJSON,
    item: HTMLElement,
  ) => {
    const destroyUrl = destroyUrlTemplate.replace(/\/0$/, `/${media.id}`);

    void fetch(destroyUrl, {
      method: 'DELETE',
      headers: { 'X-CSRF-Token': getCSRFToken() },
      credentials: 'same-origin',
    }).finally(() => {
      item.remove();
    });
  };

  const appendMedia = (media: BoardAnnouncementMediaJSON) => {
    const item = document.createElement('div');
    item.className = 'board-announcement-media__item';

    const hidden = document.createElement('input');
    hidden.type = 'hidden';
    hidden.name = fieldName;
    hidden.value = media.id;
    item.appendChild(hidden);

    const trigger = document.createElement('button');
    trigger.type = 'button';
    trigger.className = 'board-announcement-media__thumb';
    trigger.title = labels.copy;

    if (media.type === 'image') {
      const img = document.createElement('img');
      img.src = media.preview_url;
      img.alt = media.file_name;
      trigger.appendChild(img);
    } else {
      const name = document.createElement('span');
      name.className = 'board-announcement-media__name';
      name.textContent = media.file_name;
      trigger.appendChild(name);
    }

    trigger.addEventListener('click', () => {
      void copyToClipboard(buildMarkdown(media)).then(() => {
        showStatus(labels.copied, false);
      });
    });

    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'board-announcement-media__remove';
    remove.setAttribute('aria-label', labels.remove);
    remove.title = labels.remove;
    remove.textContent = '×';
    remove.addEventListener('click', () => {
      removeMedia(media, item);
    });

    item.appendChild(trigger);
    item.appendChild(remove);
    list.appendChild(item);
  };

  const uploadFile = async (file: File) => {
    const body = new FormData();
    body.append('file', file);

    const response = await fetch(uploadUrl, {
      method: 'POST',
      headers: { 'X-CSRF-Token': getCSRFToken() },
      credentials: 'same-origin',
      body,
    });

    if (!response.ok) {
      throw new Error(labels.error);
    }

    return (await response.json()) as BoardAnnouncementMediaJSON;
  };

  fileInput.addEventListener('change', () => {
    const files = Array.from(fileInput.files ?? []);
    fileInput.value = '';

    if (files.length === 0) return;

    showStatus(labels.uploading, false);
    addButton.disabled = true;

    void (async () => {
      try {
        for (const file of files) {
          const media = await uploadFile(file);
          appendMedia(media);
        }
        clearStatus();
      } catch {
        showStatus(labels.error, true);
      } finally {
        addButton.disabled = false;
      }
    })();
  });

  existing.forEach(appendMedia);

  container.appendChild(list);
  container.appendChild(status);
  container.appendChild(addButton);
  container.appendChild(fileInput);
}

export function initBoardAnnouncementMedia() {
  document
    .querySelectorAll<HTMLElement>('[data-board-announcement-media]')
    .forEach((container) => {
      if (container.dataset.boardAnnouncementMediaReady === 'true') return;

      container.dataset.boardAnnouncementMediaReady = 'true';
      setupBoardAnnouncementMedia(container);
    });
}
