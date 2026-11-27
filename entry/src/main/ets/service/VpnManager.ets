import { Want } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';
import { commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import tizlinkNative from 'libtizlink_native.so';
import { AppSettings, ProxyNode, RoutingMode, TrafficStats, VpnState } from '../model/Models';
import { StorageService } from './StorageService';
import { MihomoConfigBuilder } from './MihomoConfigBuilder';
import { MihomoControllerService } from './MihomoControllerService';
import { APP_BUNDLE_NAME, VPN_STATUS_EVENT } from '../vpn/TizLinkVpnExtensionAbility';

const DOMAIN: number = 0x3200;
const TAG: string = 'VpnManager';

export type VpnUpdateListener = (state: VpnState, traffic: TrafficStats, errorMsg: string) => void;

export class VpnManager {
  private static instance: VpnManager | null = null;
  private subscriber: commonEventManager.CommonEventSubscriber | null = null;
  private listeners: Set<VpnUpdateListener> = new Set<VpnUpdateListener>();
  private currentState: VpnState = 'disconnected';
  private currentTraffic: TrafficStats = { up: 0, down: 0, upTotal: 0, downTotal: 0 };

  static getInstance(): VpnManager {
    if (!VpnManager.instance) {
      VpnManager.instance = new VpnManager();
    }
    return VpnManager.instance;
  }

  async init(): Promise<void> {
    const savedState: string = await StorageService.getInstance().getVpnRuntimeState();
    if (savedState === 'connected' && tizlinkNative.isRunning()) {
      this.currentState = 'connected';
    } else {
      this.currentState = 'disconnected';
    }
    await this.subscribeEvents();
  }

  addListener(listener: VpnUpdateListener): void {
    this.listeners.add(listener);
    listener(this.currentState, this.currentTraffic, '');
  }

  removeListener(listener: VpnUpdateListener): void {
    this.listeners.delete(listener);
  }

  getState(): VpnState {
    return this.currentState;
  }

  getCoreVersion(): string {
    try {
      return tizlinkNative.getVersion();
    } catch (_e) {
      return 'mihomo (harmonyos)';
    }
  }

  isCoreAvailable(): boolean {
    try {
      return tizlinkNative.isCoreAvailable();
    } catch (_e) {
      return false;
    }
  }

  getNativeLogs(): string {
    try {
      return tizlinkNative.getLogs();
    } catch (_e) {
      return '';
    }
  }

  clearNativeLogs(): void {
    try {
      tizlinkNative.clearLogs();
    } catch (_e) {
      // ignore
    }
  }

  async connect(
    nodes: ProxyNode[],
    selectedNodeId: string,
    settings: AppSettings
  ): Promise<string> {
    if (nodes.length === 0) {
      return '暂无可用节点，请先刷新订阅或导入节点';
    }
    this.notifyListeners('connecting', { up: 0, down: 0, upTotal: 0, downTotal: 0 }, '');

    const configYaml: string = MihomoConfigBuilder.buildConfigYaml(nodes, selectedNodeId, settings);
    await StorageService.getInstance().saveLastConfigYaml(configYaml);

    const want: Want = {
      bundleName: APP_BUNDLE_NAME,
      abilityName: 'TizLinkVpnExtensionAbility',
      parameters: {
        'configYaml': configYaml
      }
    };

    try {
      await vpnExtension.startVpnExtensionAbility(want);
      hilog.info(DOMAIN, TAG, 'startVpnExtensionAbility invoked');
      return '';
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'startVpnExtensionAbility failed: %{public}s', msg);
      this.notifyListeners('disconnected', { up: 0, down: 0, upTotal: 0, downTotal: 0 }, msg);
      return `启动 VPN 失败: ${msg}`;
    }
  }

  async disconnect(): Promise<void> {
    this.notifyListeners('disconnecting', this.currentTraffic, '');
    const want: Want = {
      bundleName: APP_BUNDLE_NAME,
      abilityName: 'TizLinkVpnExtensionAbility'
    };
    try {
      await vpnExtension.stopVpnExtensionAbility(want);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'stopVpnExtensionAbility error: %{public}s', JSON.stringify(err));
    }
    try {
      tizlinkNative.stop();
    } catch (_e) {
      // ignore
    }
    await StorageService.getInstance().setVpnRuntimeState('disconnected');
    this.notifyListeners('disconnected', { up: 0, down: 0, upTotal: 0, downTotal: 0 }, '');
  }

  async hotSwitchNode(nodeName: string, controllerPort: number): Promise<boolean> {
    if (this.currentState !== 'connected') {
      return false;
    }
    return await MihomoControllerService.getInstance().hotSwitchNode(controllerPort, nodeName);
  }

  async switchRoutingMode(mode: RoutingMode, controllerPort: number): Promise<boolean> {
    if (this.currentState !== 'connected') {
      return false;
    }
    return await MihomoControllerService.getInstance().switchMode(controllerPort, mode);
  }

  private async subscribeEvents(): Promise<void> {
    try {
      const subInfo: commonEventManager.CommonEventSubscribeInfo = {
        events: [VPN_STATUS_EVENT]
      };
      this.subscriber = await commonEventManager.createSubscriber(subInfo);
      commonEventManager.subscribe(this.subscriber, (err, data) => {
        if (err || !data || !data.parameters) {
          return;
        }
        const params = data.parameters as Record<string, Object>;
        const stateStr: string = String(params['state'] ?? 'disconnected');
        const errMsg: string = String(params['error'] ?? '');
        const state: VpnState =
          stateStr === 'connected' || stateStr === 'connecting' || stateStr === 'disconnecting'
            ? (stateStr as VpnState)
            : 'disconnected';
        const traffic: TrafficStats = {
          up: Number(params['up'] ?? 0) || 0,
          down: Number(params['down'] ?? 0) || 0,
          upTotal: Number(params['upTotal'] ?? 0) || 0,
          downTotal: Number(params['downTotal'] ?? 0) || 0
        };
        this.notifyListeners(state, traffic, errMsg);
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'subscribeEvents failed: %{public}s', JSON.stringify(err));
    }
  }

  private notifyListeners(state: VpnState, traffic: TrafficStats, errorMsg: string): void {
    this.currentState = state;
    this.currentTraffic = traffic;
    this.listeners.forEach((listener: VpnUpdateListener) => {
      listener(state, traffic, errorMsg);
    });
  }
}
