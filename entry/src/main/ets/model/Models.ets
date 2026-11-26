export type RoutingMode = 'rule' | 'global';
export type RelayRegion = 'auto' | 'cn' | 'global';
export type SplitTunnelMode = 'bypass' | 'only';
export type AppLanguage = 'zh' | 'en';
export type VpnState = 'disconnected' | 'connecting' | 'connected' | 'disconnecting';

export interface ProxyNode {
  id: string;
  name: string;
  type: string;
  server: string;
  port: number;
  countryCode: string;
  regionLabel: string;
  latencyMs: number;
  rawYamlLines: string[];
  rawUri: string;
}

export interface SubscriptionInfo {
  planName: string;
  subscribeUrl: string;
  expiredAt: number;
  transferEnable: number;
  usedUpload: number;
  usedDownload: number;
  resetDay: number;
  email: string;
  balance: number;
  uuid: string;
}

export interface PlanItem {
  id: number;
  name: string;
  content: string;
  transferEnableGb: number;
  monthPrice: number;
  quarterPrice: number;
  halfYearPrice: number;
  yearPrice: number;
  onetimePrice: number;
  resetPrice: number;
}

export interface OrderItem {
  tradeNo: string;
  planName: string;
  period: string;
  totalAmount: number;
  status: number;
  createdAt: number;
  paymentUrl: string;
}

export interface PaymentMethod {
  id: string;
  name: string;
  payment: string;
}

export interface InviteCodeItem {
  code: string;
  status: number;
  createdAt: number;
}

export interface InviteSummary {
  codes: InviteCodeItem[];
  registeredCount: number;
  commissionRate: number;
  commissionBalance: number;
  pendingCommission: number;
}

export interface NoticeItem {
  id: number;
  title: string;
  content: string;
  createdAt: number;
}

export interface ChainProxyConfig {
  enabled: boolean;
  type: 'socks5' | 'http';
  server: string;
  port: number;
  username: string;
  password: string;
}

export interface TrafficStats {
  up: number;
  down: number;
  upTotal: number;
  downTotal: number;
}

export interface AppSettings {
  whmcsApiUrl: string;
  manualSubscribeUrl: string;
  routingMode: RoutingMode;
  relayRegion: RelayRegion;
  enableIpv6: boolean;
  enableFakeIp: boolean;
  mixedPort: number;
  controllerPort: number;
  splitTunnelEnabled: boolean;
  splitTunnelMode: SplitTunnelMode;
  splitTunnelApps: string[];
  chainProxy: ChainProxyConfig;
  crispWebsiteId: string;
  telegramUrl: string;
  language: AppLanguage;
  logLevel: string;
}

export interface AuthSession {
  loggedIn: boolean;
  email: string;
  token: string;
  authData: string;
  savedPassword: string;
  deviceId: string;
}

export interface ApiResult<T> {
  ok: boolean;
  message: string;
  data?: T;
}

export const DEFAULT_WHMCS_API_URL: string =
  'https://152.136.157.60:34814/modules/addons/v2raysocks_nodes/api/v2raysocks_client.php';

export const APP_VERSION: string = '2.0.20';

export function createDefaultSettings(): AppSettings {
  return {
    whmcsApiUrl: DEFAULT_WHMCS_API_URL,
    manualSubscribeUrl: '',
    routingMode: 'rule',
    relayRegion: 'auto',
    enableIpv6: false,
    enableFakeIp: true,
    mixedPort: 7890,
    controllerPort: 9090,
    splitTunnelEnabled: false,
    splitTunnelMode: 'bypass',
    splitTunnelApps: [],
    chainProxy: {
      enabled: false,
      type: 'socks5',
      server: '',
      port: 1080,
      username: '',
      password: ''
    },
    crispWebsiteId: '',
    telegramUrl: '',
    language: 'zh',
    logLevel: 'info'
  };
}

export function createEmptySubscription(): SubscriptionInfo {
  return {
    planName: '',
    subscribeUrl: '',
    expiredAt: 0,
    transferEnable: 0,
    usedUpload: 0,
    usedDownload: 0,
    resetDay: 0,
    email: '',
    balance: 0,
    uuid: ''
  };
}

export function formatBytes(bytes: number): string {
  if (!bytes || bytes <= 0) {
    return '0 B';
  }
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
  let idx: number = 0;
  let value: number = bytes;
  while (value >= 1024 && idx < units.length - 1) {
    value = value / 1024;
    idx++;
  }
  return `${value.toFixed(idx === 0 ? 0 : 2)} ${units[idx]}`;
}

export function formatSpeed(bytesPerSec: number): string {
  return `${formatBytes(bytesPerSec)}/s`;
}

export function formatDate(unixSeconds: number): string {
  if (!unixSeconds || unixSeconds <= 0) {
    return '--';
  }
  const ms: number = unixSeconds > 100000000000 ? unixSeconds : unixSeconds * 1000;
  const d: Date = new Date(ms);
  const y: number = d.getFullYear();
  const m: string = String(d.getMonth() + 1).padStart(2, '0');
  const day: string = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}
