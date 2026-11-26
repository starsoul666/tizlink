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

export interface ApiLineItem {
  id: string;
  name: string;
  url: string;
  latencyMs: number;
  isDefault: boolean;
}

export interface AppSettings {
  whmcsApiUrl: string;
  apiLines: ApiLineItem[];
  routingMode: RoutingMode;
  relayRegion: RelayRegion;
  enableIpv6: boolean;
  enableFakeIp: boolean;
  mixedPort: number;
  socksPort: number;
  allowLan: boolean;
  controllerPort: number;
  customDns: string[];
  customRules: string[];
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

export function createDefaultApiLines(): ApiLineItem[] {
  return [
    {
      id: 'default_primary',
      name: 'TizLink 官方主线路',
      url: DEFAULT_WHMCS_API_URL,
      latencyMs: -1,
      isDefault: true
    }
  ];
}

export function createDefaultSettings(): AppSettings {
  return {
    whmcsApiUrl: DEFAULT_WHMCS_API_URL,
    apiLines: createDefaultApiLines(),
    routingMode: 'rule',
    relayRegion: 'cn',
    enableIpv6: false,
    enableFakeIp: true,
    mixedPort: 7890,
    socksPort: 7891,
    allowLan: true,
    controllerPort: 9090,
    customDns: [],
    customRules: [],
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

export function formatDuration(totalSeconds: number): string {
  const safe: number = totalSeconds > 0 ? Math.floor(totalSeconds) : 0;
  const hrs: number = Math.floor(safe / 3600);
  const mins: number = Math.floor((safe % 3600) / 60);
  const secs: number = safe % 60;
  return `${String(hrs).padStart(2, '0')}:${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
}

export function getCountryFlag(code: string): string {
  const upper: string = (code || '').toUpperCase();
  if (upper === 'JP') return '🇯🇵';
  if (upper === 'HK') return '🇭🇰';
  if (upper === 'TW') return '🇹🇼';
  if (upper === 'SG') return '🇸🇬';
  if (upper === 'US') return '🇺🇸';
  if (upper === 'KR') return '🇰🇷';
  if (upper === 'UK' || upper === 'GB') return '🇬🇧';
  if (upper === 'DE') return '🇩🇪';
  if (upper === 'FR') return '🇫🇷';
  if (upper === 'CA') return '🇨🇦';
  if (upper === 'AU') return '🇦🇺';
  if (upper === 'NL') return '🇳🇱';
  if (upper === 'IN') return '🇮🇳';
  if (upper === 'RU') return '🇷🇺';
  if (upper === 'TR') return '🇹🇷';
  if (upper === 'MY') return '🇲🇾';
  if (upper === 'TH') return '🇹🇭';
  if (upper === 'VN') return '🇻🇳';
  if (upper === 'PH') return '🇵🇭';
  if (upper === 'CN') return '🇨🇳';
  return '🌐';
}
