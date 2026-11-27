const listeners = new Set();

export const subscribeComposeSubmitSuccess = (listener) => {
  listeners.add(listener);

  return () => {
    listeners.delete(listener);
  };
};

export const notifyComposeSubmitSuccess = (status) => {
  listeners.forEach((listener) => {
    listener(status);
  });
};
