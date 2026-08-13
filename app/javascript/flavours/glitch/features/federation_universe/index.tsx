import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Helmet } from '@unhead/react/helmet';

import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import FullscreenIcon from '@/material-icons/400-24px/fullscreen.svg?react';
import FullscreenExitIcon from '@/material-icons/400-24px/fullscreen_exit.svg?react';
import PublicIcon from '@/material-icons/400-24px/public.svg?react';
import type {
  ApiFederationUniverse,
  ApiFederationUniverseEdge,
} from 'flavours/glitch/api/federation_universe';
import { apiGetFederationUniverse } from 'flavours/glitch/api/federation_universe';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column/header';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { LoadingIndicator } from 'flavours/glitch/components/loading_indicator';
import {
  attachFullscreenListener,
  detachFullscreenListener,
  exitFullscreen,
  isFullscreen,
  requestFullscreen,
} from 'flavours/glitch/features/ui/util/fullscreen';

import { FederationUniverseCanvas } from './canvas';
import type { UniverseNode } from './layout';
import { buildUniverseLayout } from './layout';

const messages = defineMessages({
  title: {
    id: 'federation_universe.title',
    defaultMessage: 'Federation universe',
  },
  close: { id: 'federation_universe.close', defaultMessage: 'Close details' },
  enterFullscreen: {
    id: 'federation_universe.enter_fullscreen',
    defaultMessage: 'Enter full screen',
  },
  exitFullscreen: {
    id: 'federation_universe.exit_fullscreen',
    defaultMessage: 'Exit full screen',
  },
  loadError: {
    id: 'federation_universe.load_error',
    defaultMessage: 'The federation universe could not be loaded.',
  },
  users: { id: 'federation_universe.users', defaultMessage: 'Users' },
  gone: { id: 'federation_universe.gone', defaultMessage: 'Gone server' },
  posts: { id: 'federation_universe.posts', defaultMessage: 'Posts' },
  interactions: {
    id: 'federation_universe.interactions_heading',
    defaultMessage: 'Observed interactions',
  },
  reblogs: { id: 'federation_universe.reblogs', defaultMessage: 'Boosts' },
  replies: { id: 'federation_universe.replies', defaultMessage: 'Replies' },
  quotes: { id: 'federation_universe.quotes', defaultMessage: 'Quotes' },
  connections: {
    id: 'federation_universe.connections',
    defaultMessage: 'Connected servers',
  },
  noConnections: {
    id: 'federation_universe.no_connections',
    defaultMessage: 'No connected servers were observed.',
  },
  interactionCount: {
    id: 'federation_universe.interactions',
    defaultMessage: '{count, number} interactions',
  },
  distance: {
    id: 'federation_universe.distance',
    defaultMessage: 'Distance from this server',
  },
  distanceValue: {
    id: 'federation_universe.distance_value',
    defaultMessage: '{count, number} map units',
  },
});

const sumEdges = (edges: ApiFederationUniverseEdge[]) =>
  edges.reduce(
    (total, edge) => ({
      interactions: total.interactions + edge.interactions,
      reblogs: total.reblogs + edge.reblogs,
      replies: total.replies + edge.replies,
      quotes: total.quotes + edge.quotes,
    }),
    { interactions: 0, reblogs: 0, replies: 0, quotes: 0 },
  );

export const FederationUniverse: React.FC<{ multiColumn?: boolean }> = ({
  multiColumn,
}) => {
  const intl = useIntl();
  const bodyRef = useRef<HTMLDivElement>(null);
  const [universe, setUniverse] = useState<ApiFederationUniverse | null>(null);
  const [selected, setSelected] = useState<UniverseNode | null>(null);
  const [failed, setFailed] = useState(false);
  const [fullscreen, setFullscreen] = useState(false);
  const nodes = useMemo(
    () => (universe ? buildUniverseLayout(universe) : []),
    [universe],
  );

  useEffect(() => {
    const handleFullscreenChange = () => {
      setFullscreen(isFullscreen());
    };

    attachFullscreenListener(handleFullscreenChange);
    return () => {
      detachFullscreenListener(handleFullscreenChange);
    };
  }, []);

  useEffect(() => {
    let active = true;
    void apiGetFederationUniverse()
      .then((result) => {
        if (active) setUniverse(result);
      })
      .catch(() => {
        if (active) setFailed(true);
      });

    return () => {
      active = false;
    };
  }, []);

  const selectedEdges = useMemo(() => {
    if (!selected || !universe) return [];
    return universe.edges.filter(
      (edge) => edge.source === selected.id || edge.target === selected.id,
    );
  }, [selected, universe]);

  const selectedTotals = useMemo(
    () => (selected ? sumEdges(selectedEdges) : null),
    [selected, selectedEdges],
  );

  const selectedConnections = useMemo(() => {
    if (!selected || !universe) return [];
    const nodesById = new Map(nodes.map((node) => [node.id, node]));
    const connections = new Map<
      string,
      { node: UniverseNode; edges: ApiFederationUniverseEdge[] }
    >();

    for (const edge of selectedEdges) {
      const connectedId =
        edge.source === selected.id ? edge.target : edge.source;
      const node = nodesById.get(connectedId);
      if (!node) continue;
      const connection = connections.get(connectedId) ?? { node, edges: [] };
      connection.edges.push(edge);
      connections.set(connectedId, connection);
    }

    return [...connections.values()]
      .map((connection) => ({
        node: connection.node,
        totals: sumEdges(connection.edges),
      }))
      .sort(
        (first, second) =>
          second.totals.interactions - first.totals.interactions ||
          first.node.domain.localeCompare(second.node.domain),
      );
  }, [nodes, selected, selectedEdges, universe]);

  const handleSelect = useCallback((node: UniverseNode | null) => {
    setSelected(node);
  }, []);

  const handleConnectionSelect = useCallback(
    (event: React.MouseEvent<HTMLButtonElement>) => {
      const node = nodes.find(
        (candidate) => candidate.id === event.currentTarget.dataset.nodeId,
      );
      if (node) setSelected(node);
    },
    [nodes],
  );

  const handleCloseDetails = useCallback(() => {
    setSelected(null);
  }, []);

  const handleFullscreen = useCallback(() => {
    if (isFullscreen()) exitFullscreen();
    else requestFullscreen(bodyRef.current);
  }, []);

  return (
    <Column
      bindToDocument={!multiColumn}
      label={intl.formatMessage(messages.title)}
      className='federation-universe'
    >
      <ColumnHeader
        icon='globe'
        iconComponent={PublicIcon}
        title={intl.formatMessage(messages.title)}
        multiColumn={multiColumn}
        showBackButton
      />

      <div
        ref={bodyRef}
        className={`federation-universe__body${selected ? ' federation-universe__body--selected' : ''}`}
      >
        {!universe && !failed && <LoadingIndicator />}
        {failed && (
          <div className='federation-universe__error'>
            {intl.formatMessage(messages.loadError)}
          </div>
        )}
        {universe && (
          <>
            <FederationUniverseCanvas
              universe={universe}
              nodes={nodes}
              selectedId={selected?.id ?? null}
              onSelect={handleSelect}
            />
            <div className='federation-universe__legend'>
              <span>
                <FormattedMessage
                  id='federation_universe.drag_hint'
                  defaultMessage='Drag to orbit'
                />
              </span>
              <span>
                <FormattedMessage
                  id='federation_universe.zoom_hint'
                  defaultMessage='Scroll to travel'
                />
              </span>
              <span>
                <FormattedMessage
                  id='federation_universe.navigation_hint'
                  defaultMessage='WASD · Space/C to move'
                />
              </span>
              <span>
                {universe.nodes.length.toLocaleString()}{' '}
                <FormattedMessage
                  id='federation_universe.servers'
                  defaultMessage='servers'
                />
              </span>
            </div>
            <IconButton
              className='federation-universe__fullscreen'
              icon={fullscreen ? 'compress' : 'expand'}
              iconComponent={fullscreen ? FullscreenExitIcon : FullscreenIcon}
              title={intl.formatMessage(
                fullscreen ? messages.exitFullscreen : messages.enterFullscreen,
              )}
              onClick={handleFullscreen}
            />
          </>
        )}

        {selected && selectedTotals && (
          <aside className='federation-universe__details' aria-live='polite'>
            <IconButton
              className='federation-universe__details-close'
              icon='times'
              iconComponent={CloseIcon}
              title={intl.formatMessage(messages.close)}
              onClick={handleCloseDetails}
            />
            <div className='federation-universe__details-kicker'>
              {selected.gone
                ? intl.formatMessage(messages.gone)
                : (selected.software ?? (
                    <FormattedMessage
                      id='federation_universe.unknown_software'
                      defaultMessage='Unknown system'
                    />
                  ))}
            </div>
            <h2>{selected.name}</h2>
            <div className='federation-universe__details-domain'>
              {selected.domain}
            </div>
            <dl className='federation-universe__metrics'>
              <div>
                <dt>{intl.formatMessage(messages.posts)}</dt>
                <dd>{selected.posts.toLocaleString()}</dd>
              </div>
              <div>
                <dt>{intl.formatMessage(messages.interactions)}</dt>
                <dd>{selectedTotals.interactions.toLocaleString()}</dd>
              </div>
            </dl>
            <div className='federation-universe__signals'>
              <span>
                {intl.formatMessage(messages.users)}{' '}
                <strong>{selected.users.toLocaleString()}</strong>
              </span>
              <span>
                {intl.formatMessage(messages.reblogs)}{' '}
                <strong>{selectedTotals.reblogs.toLocaleString()}</strong>
              </span>
              <span>
                {intl.formatMessage(messages.replies)}{' '}
                <strong>{selectedTotals.replies.toLocaleString()}</strong>
              </span>
              <span>
                {intl.formatMessage(messages.quotes)}{' '}
                <strong>{selectedTotals.quotes.toLocaleString()}</strong>
              </span>
            </div>
            <div className='federation-universe__distance'>
              <span>{intl.formatMessage(messages.distance)}</span>
              <strong>
                {intl.formatMessage(messages.distanceValue, {
                  count: Math.round(
                    Math.hypot(selected.x, selected.y, selected.z),
                  ),
                })}
              </strong>
            </div>
            <section className='federation-universe__connections'>
              <h3>
                {intl.formatMessage(messages.connections)}
                <span>{selectedConnections.length.toLocaleString()}</span>
              </h3>
              {selectedConnections.length > 0 ? (
                <ul>
                  {selectedConnections.map((connection) => (
                    <li key={connection.node.id}>
                      <button
                        type='button'
                        data-node-id={connection.node.id}
                        onClick={handleConnectionSelect}
                      >
                        <span className='federation-universe__connection-name'>
                          <strong>{connection.node.name}</strong>
                          <span>{connection.node.domain}</span>
                        </span>
                        <span className='federation-universe__connection-count'>
                          {intl.formatMessage(messages.interactionCount, {
                            count: connection.totals.interactions,
                          })}
                        </span>
                      </button>
                    </li>
                  ))}
                </ul>
              ) : (
                <p>{intl.formatMessage(messages.noConnections)}</p>
              )}
            </section>
          </aside>
        )}
      </div>

      <Helmet>
        <title>{intl.formatMessage(messages.title)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};
