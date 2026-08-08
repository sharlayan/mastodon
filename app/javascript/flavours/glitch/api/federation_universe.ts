import { apiRequestGet } from 'flavours/glitch/api';

export interface ApiFederationUniverseNode {
  id: string;
  domain: string;
  name: string;
  software: string | null;
  color: string | null;
  users: number;
  posts: number;
  local?: boolean;
  gone: boolean;
}

export interface ApiFederationUniverseEdge {
  source: string;
  target: string;
  interactions: number;
  reblogs: number;
  replies: number;
  quotes: number;
}

export interface ApiFederationUniverse {
  local_domain: string;
  generated_at: string | null;
  nodes: ApiFederationUniverseNode[];
  edges: ApiFederationUniverseEdge[];
}

export const apiGetFederationUniverse = () =>
  apiRequestGet<ApiFederationUniverse>('v1/federation_universe');
