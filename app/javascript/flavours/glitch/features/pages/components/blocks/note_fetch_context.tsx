import { createContext, useCallback, useContext, useMemo, useRef } from 'react';

interface PageNoteFetchGate {
  begin: (statusId: string) => boolean;
  finish: (statusId: string) => void;
}

const PageNoteFetchContext = createContext<PageNoteFetchGate | null>(null);

export const PageNoteFetchProvider: React.FC<React.PropsWithChildren> = ({
  children,
}) => {
  const pendingStatusIds = useRef(new Set<string>());
  const begin = useCallback((statusId: string) => {
    if (pendingStatusIds.current.has(statusId)) {
      return false;
    }

    pendingStatusIds.current.add(statusId);
    return true;
  }, []);
  const finish = useCallback((statusId: string) => {
    pendingStatusIds.current.delete(statusId);
  }, []);
  const gate = useMemo(() => ({ begin, finish }), [begin, finish]);

  return (
    <PageNoteFetchContext.Provider value={gate}>
      {children}
    </PageNoteFetchContext.Provider>
  );
};

export const usePageNoteFetch = () => {
  const gate = useContext(PageNoteFetchContext);

  if (!gate) {
    throw new Error(
      'usePageNoteFetch must be used within PageNoteFetchProvider',
    );
  }

  return gate;
};
