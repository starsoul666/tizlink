import { preferences } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ApiLineItem,
  AppSettings,
  AuthSession,
  createDefaultApiLines,
  createDefaultSettings,
  createEmptySubscription,
  ProxyNode,
  SubscriptionInfo
} from '../model/Models';

const DOMAIN: number = 0x3200;
const TAG: string = 'StorageService';
const PREF_NAME: string = 'tizlink_store';

const KEY_AUTH: string = 'auth_session';
const KEY_SETTINGS: string = 'app_settings';
const KEY_SUBSCRIPTION: string = 'subscription_info';
const KEY_NODES: string = 'proxy_nodes';
const KEY_SELECTED_NODE: string = 'selected_node_id';
const KEY_LAST_CONFIG: string = 'last_mihomo_config';
const KEY_DEVICE_ID: string = 'aegis_device_id';
const KEY_VPN_STATE: string = 'vpn_runtime_state';

export class StorageService {
  private static instance: StorageService | null = null;
  private pref: preferences.Preferences | null = null;
  private filesDir: string = '';

  static getInstance(): StorageService {
    if (!StorageService.instance) {
      StorageService.instance = new StorageService();
    }
    return StorageService.instance;
  }

  async init(context: common.Context): Promise<void> {
    this.filesDir = context.filesDir;
    this.pref = await preferences.getPreferences(context, PREF_NAME);
    await this.ensureGeoDataCopied(context);
  }

  getMihomoHomeDir(): string {
    return `${this.filesDir}/mihomo`;
  }

  async ensureGeoDataCopied(context: common.Context): Promise<void> {
    const mihomoDir: string = this.getMihomoHomeDir();
    try {
      if (!fs.accessSync(mihomoDir)) {
        fs.mkdirSync(mihomoDir, true);
      }
    } catch (_e) {
      try {
        fs.mkdirSync(mihomoDir, true);
      } catch (mkdirErr) {
        hilog.error(DOMAIN, TAG, 'mkdir mihomo failed: %{public}s', JSON.stringify(mkdirErr));
      }
    }

    const assets: string[] = ['country.mmdb', 'geoip.dat', 'geosite.dat'];
    for (const fileName of assets) {
      const targetPath: string = `${mihomoDir}/${fileName}`;
      try {
        if (fs.accessSync(targetPath)) {
          const stat = fs.statSync(targetPath);
          if (stat.size > 1024) {
            continue;
          }
        }
      } catch (_e) {
        // Needs copy
      }

      try {
        const rawBytes: Uint8Array = await context.resourceManager.getRawFileContent(`geodata/${fileName}`);
        const file = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        fs.writeSync(file.fd, rawBytes.buffer);
        fs.closeSync(file.fd);
        hilog.info(DOMAIN, TAG, 'Copied geodata %{public}s (%{public}d bytes)', fileName, rawBytes.byteLength);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'Failed to copy %{public}s: %{public}s', fileName, JSON.stringify(err));
      }
    }
  }

  async getOrCreateDeviceId(): Promise<string> {
    const existing: string = await this.getString(KEY_DEVICE_ID, '');
    if (existing.length > 0) {
      return existing;
    }
    const chars: string = '0123456789abcdef';
    let id: string = 'ohos-';
    for (let i: number = 0; i < 24; i++) {
      id += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    await this.putString(KEY_DEVICE_ID, id);
    return id;
  }

  async loadAuth(): Promise<AuthSession> {
    const deviceId: string = await this.getOrCreateDeviceId();
    const raw: string = await this.getString(KEY_AUTH, '');
    if (raw.length > 0) {
      try {
        const parsed = JSON.parse(raw) as AuthSession;
        if (!parsed.deviceId) {
          parsed.deviceId = deviceId;
        }
        return parsed;
      } catch (_e) {
        // fallback
      }
    }
    return {
      loggedIn: false,
      email: '',
      token: '',
      authData: '',
      savedPassword: '',
      deviceId: deviceId
    };
  }

  async saveAuth(session: AuthSession): Promise<void> {
    await this.putString(KEY_AUTH, JSON.stringify(session));
  }

  async clearAuth(): Promise<void> {
    const prev: AuthSession = await this.loadAuth();
    const cleared: AuthSession = {
      loggedIn: false,
      email: prev.email,
      token: '',
      authData: '',
      savedPassword: '',
      deviceId: prev.deviceId
    };
    await this.saveAuth(cleared);
  }

  async loadSettings(): Promise<AppSettings> {
    const defaults: AppSettings = createDefaultSettings();
    const raw: string = await this.getString(KEY_SETTINGS, '');
    if (raw.length === 0) {
      return defaults;
    }
    try {
      const saved = JSON.parse(raw) as Partial<AppSettings>;
      const rawWhmcsUrl: string = (saved.whmcsApiUrl ?? defaults.whmcsApiUrl).trim();
      const fixedWhmcsUrl: string = rawWhmcsUrl.includes('152.1p36.157.60')
        ? defaults.whmcsApiUrl
        : (rawWhmcsUrl.length > 0 ? rawWhmcsUrl : defaults.whmcsApiUrl);
      const rawLines: ApiLineItem[] = (saved.apiLines && saved.apiLines.length > 0)
        ? saved.apiLines.map((line: ApiLineItem) => {
            const fixedUrl: string = line.url.includes('152.1p36.157.60') ? defaults.whmcsApiUrl : line.url;
            return {
              id: line.id,
              name: line.name,
              url: fixedUrl,
              latencyMs: line.latencyMs,
              isDefault: line.isDefault
            } as ApiLineItem;
          })
        : createDefaultApiLines();
      return {
        whmcsApiUrl: fixedWhmcsUrl,
        apiLines: rawLines,
        routingMode: saved.routingMode ?? defaults.routingMode,
        relayRegion: saved.relayRegion ?? defaults.relayRegion,
        enableIpv6: saved.enableIpv6 ?? defaults.enableIpv6,
        enableFakeIp: saved.enableFakeIp ?? defaults.enableFakeIp,
        mixedPort: saved.mixedPort ?? defaults.mixedPort,
        socksPort: saved.socksPort ?? defaults.socksPort,
        allowLan: saved.allowLan ?? defaults.allowLan,
        controllerPort: saved.controllerPort ?? defaults.controllerPort,
        customDns: saved.customDns ?? defaults.customDns,
        customRules: saved.customRules ?? defaults.customRules,
        splitTunnelEnabled: saved.splitTunnelEnabled ?? defaults.splitTunnelEnabled,
        splitTunnelMode: saved.splitTunnelMode ?? defaults.splitTunnelMode,
        splitTunnelApps: saved.splitTunnelApps ?? defaults.splitTunnelApps,
        chainProxy: saved.chainProxy ?? defaults.chainProxy,
        crispWebsiteId: saved.crispWebsiteId ?? defaults.crispWebsiteId,
        telegramUrl: saved.telegramUrl ?? defaults.telegramUrl,
        language: saved.language ?? defaults.language,
        logLevel: saved.logLevel ?? defaults.logLevel
      };
    } catch (_e) {
      return defaults;
    }
  }

  async saveSettings(settings: AppSettings): Promise<void> {
    await this.putString(KEY_SETTINGS, JSON.stringify(settings));
  }

  async loadSubscription(): Promise<SubscriptionInfo> {
    const raw: string = await this.getString(KEY_SUBSCRIPTION, '');
    if (raw.length > 0) {
      try {
        return JSON.parse(raw) as SubscriptionInfo;
      } catch (_e) {
        // fallback
      }
    }
    return createEmptySubscription();
  }

  async saveSubscription(info: SubscriptionInfo): Promise<void> {
    await this.putString(KEY_SUBSCRIPTION, JSON.stringify(info));
  }

  async loadNodes(): Promise<ProxyNode[]> {
    const raw: string = await this.getString(KEY_NODES, '');
    if (raw.length > 0) {
      try {
        return JSON.parse(raw) as ProxyNode[];
      } catch (_e) {
        // fallback
      }
    }
    return [];
  }

  async saveNodes(nodes: ProxyNode[]): Promise<void> {
    await this.putString(KEY_NODES, JSON.stringify(nodes));
  }

  async getSelectedNodeId(): Promise<string> {
    return await this.getString(KEY_SELECTED_NODE, '');
  }

  async setSelectedNodeId(id: string): Promise<void> {
    await this.putString(KEY_SELECTED_NODE, id);
  }

  async saveLastConfigYaml(yaml: string): Promise<void> {
    await this.putString(KEY_LAST_CONFIG, yaml);
    const configPath: string = `${this.getMihomoHomeDir()}/config.yaml`;
    try {
      const file = fs.openSync(configPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, yaml);
      fs.closeSync(file.fd);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Write config.yaml failed: %{public}s', JSON.stringify(err));
    }
  }

  async loadLastConfigYaml(): Promise<string> {
    return await this.getString(KEY_LAST_CONFIG, '');
  }

  async setVpnRuntimeState(state: string): Promise<void> {
    await this.putString(KEY_VPN_STATE, state);
  }

  async getVpnRuntimeState(): Promise<string> {
    return await this.getString(KEY_VPN_STATE, 'disconnected');
  }

  private async getString(key: string, defaultValue: string): Promise<string> {
    if (!this.pref) {
      return defaultValue;
    }
    try {
      const val = await this.pref.get(key, defaultValue);
      return typeof val === 'string' ? val : defaultValue;
    } catch (_e) {
      return defaultValue;
    }
  }

  private async putString(key: string, value: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    try {
      await this.pref.put(key, value);
      await this.pref.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'putString %{public}s failed: %{public}s', key, JSON.stringify(err));
    }
  }
}
