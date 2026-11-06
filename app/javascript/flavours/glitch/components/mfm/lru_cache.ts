const DEFAULT_CACHE_LIMIT = 500;

export function createLruCache<T>(limit = DEFAULT_CACHE_LIMIT) {
  const entries = new Map<string, T>();

  return (key: string, compute: () => T): T => {
    if (entries.has(key)) {
      const value = entries.get(key) as T;
      entries.delete(key);
      entries.set(key, value);
      return value;
    }

    const value = compute();
    entries.set(key, value);

    if (entries.size > limit) {
      const oldest = entries.keys().next().value;
      if (oldest !== undefined) entries.delete(oldest);
    }

    return value;
  };
}
