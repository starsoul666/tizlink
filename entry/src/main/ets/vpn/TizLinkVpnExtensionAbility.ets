import { Want } from '@kit.AbilityKit';
import { connection, vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import { commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import tizlinkNative from 'libtizlink_native.so';
import { AppSettings, TrafficStats } from '../model/Models';
import { StorageService } from '../service/StorageService';

const DOMAIN: number = 0x3200;
const TAG: string = 'TizLinkVpnExt';
export const APP_BUNDLE_NAME: string = 'com.tizlink.app';
export const VPN_STATUS_EVENT: string = `${APP_BUNDLE_NAME}.VPN_STATUS`;

export default class TizLinkVpnExtensionAbility extends VpnExtensionAbility {
  private vpnConnection: vpnExtension.VpnConnection | null = null;
  private netConn: connection.NetConnection | null = null;
  private trafficTimerId: number = -1;
  private tunFd: number = -1;

  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'TizLinkVpnExtensionAbility onCreate');
    void this.startVpnPipeline(want);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'TizLinkVpnExtensionAbility onDestroy');
    void this.stopVpnPipeline();
  }

  private async startVpnPipeline(want: Want): Promise<void> {
    const storage: StorageService = StorageService.getInstance();
    try {
      await storage.init(this.context);
      await storage.setVpnRuntimeState('connecting');
      this.publishStatus('connecting', '', 0, 0, 0, 0);

      const settings: AppSettings = await storage.loadSettings();
      let configYaml: string = '';
      if (want.parameters && typeof want.parameters['configYaml'] === 'string') {
        configYaml = want.parameters['configYaml'] as string;
      }
      if (configYaml.length === 0) {
        configYaml = await storage.loadLastConfigYaml();
      }
      if (configYaml.trim().length === 0) {
        throw new Error('Mihomo 配置为空，请先同步订阅并选择节点');
      }

      if (!tizlinkNative.isCoreAvailable()) {
        throw new Error('原生 Mihomo 核心 (libmihomo.so) 未加载');
      }

      const homeDir: string = storage.getMihomoHomeDir();
      const setupErr: string = tizlinkNative.setup(homeDir);
      if (setupErr.length > 0) {
        throw new Error(`Mihomo Setup 失败: ${setupErr}`);
      }
      tizlinkNative.setLogLevel(settings.logLevel);

      // Build HarmonyOS VpnConfig matching TizLink Android (172.19.0.1/30, DNS 172.19.0.2, MTU 1500)
      const vpnConfig: vpnExtension.VpnConfig = {
        addresses: [
          {
            address: { address: '172.19.0.1', family: 1 },
            prefixLength: 30
          }
        ],
        routes: [
          {
            interface: 'vpn-tun',
            destination: {
              address: { address: '0.0.0.0', family: 1 },
              prefixLength: 0
            },
            gateway: { address: '', family: 1 },
            hasGateway: true,
            isDefaultRoute: true
          }
        ],
        dnsAddresses: ['172.19.0.2'],
        mtu: 1500,
        isIPv4Accepted: true,
        isIPv6Accepted: settings.enableIpv6,
        isInternal: false,
        isBlocking: false
      };

      // Split tunneling & self-exclusion to prevent VPN routing loop
      const ownBundle: string = APP_BUNDLE_NAME;
      if (settings.splitTunnelEnabled && settings.splitTunnelMode === 'only' && settings.splitTunnelApps.length > 0) {
        vpnConfig.trustedApplications = settings.splitTunnelApps.filter((pkg: string) => pkg !== ownBundle);
      } else {
        const blocked: string[] = [ownBundle];
        if (settings.splitTunnelEnabled && settings.splitTunnelMode === 'bypass') {
          for (const pkg of settings.splitTunnelApps) {
            if (pkg.length > 0 && !blocked.includes(pkg)) {
              blocked.push(pkg);
            }
          }
        }
        vpnConfig.blockedApplications = blocked;
      }

      this.vpnConnection = vpnExtension.createVpnConnection(this.context);

      // Register per-socket protection fallback bridge before starting TUN
      tizlinkNative.setProcessProtected(false);
      tizlinkNative.registerProtectCallback((reqId: number, fd: number) => {
        if (!this.vpnConnection) {
          tizlinkNative.resolveProtect(reqId, false);
          return;
        }
        this.vpnConnection.protect(fd).then(() => {
          tizlinkNative.resolveProtect(reqId, true);
        }).catch((err: Error) => {
          hilog.warn(DOMAIN, TAG, 'protect(%{public}d) failed: %{public}s', fd, JSON.stringify(err));
          tizlinkNative.resolveProtect(reqId, false);
        });
      });

      this.tunFd = await this.vpnConnection.create(vpnConfig);
      hilog.info(DOMAIN, TAG, 'HarmonyOS VPN TUN created, fd=%{public}d', this.tunFd);

      if (this.tunFd <= 0) {
        throw new Error(`创建 TUN 接口失败 (fd=${this.tunFd})`);
      }

      // HarmonyOS API 22+: protect entire VPN process so all outbound sockets bypass VPN natively
      try {
        await this.vpnConnection.protectProcessNet();
        tizlinkNative.setProcessProtected(true);
        hilog.info(DOMAIN, TAG, 'vpnConnection.protectProcessNet() succeeded');
      } catch (protectErr) {
        hilog.warn(DOMAIN, TAG, 'protectProcessNet unavailable, using per-socket protect: %{public}s', JSON.stringify(protectErr));
      }

      // Start Mihomo asynchronously off the ArkTS main thread to prevent protect(fd) deadlock
      const startErr: string = await tizlinkNative.startTunAsync(this.tunFd, configYaml);
      if (startErr.length > 0) {
        throw new Error(`Mihomo StartTun 失败: ${startErr}`);
      }

      this.registerNetworkObserver();
      this.startTrafficBroadcast();

      await storage.setVpnRuntimeState('connected');
      this.publishStatus('connected', '', 0, 0, 0, 0);
      hilog.info(DOMAIN, TAG, 'TizLink Mihomo VPN started successfully');
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'startVpnPipeline failed: %{public}s', msg);
      await storage.setVpnRuntimeState('disconnected');
      this.publishStatus('disconnected', msg, 0, 0, 0, 0);
      await this.stopVpnPipeline();
    }
  }

  private async stopVpnPipeline(): Promise<void> {
    if (this.trafficTimerId !== -1) {
      clearInterval(this.trafficTimerId);
      this.trafficTimerId = -1;
    }

    if (this.netConn) {
      try {
        this.netConn.unregister(() => {});
      } catch (_e) {
        // ignore
      }
      this.netConn = null;
    }

    try {
      tizlinkNative.stop();
      tizlinkNative.setProcessProtected(false);
      tizlinkNative.registerProtectCallback(null);
    } catch (_e) {
      // ignore
    }

    if (this.vpnConnection) {
      try {
        await this.vpnConnection.destroy();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'vpnConnection.destroy error: %{public}s', JSON.stringify(err));
      }
      this.vpnConnection = null;
    }
    this.tunFd = -1;

    try {
      await StorageService.getInstance().setVpnRuntimeState('disconnected');
    } catch (_e) {
      // ignore
    }
    this.publishStatus('disconnected', '', 0, 0, 0, 0);
  }

  private registerNetworkObserver(): void {
    try {
      this.netConn = connection.createNetConnection();
      this.netConn.register(() => {});
      this.netConn.on('netAvailable', () => {
        tizlinkNative.notifyNetworkChange();
      });
      this.netConn.on('netCapabilitiesChange', () => {
        tizlinkNative.notifyNetworkChange();
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'registerNetworkObserver failed: %{public}s', JSON.stringify(err));
    }
  }

  private startTrafficBroadcast(): void {
    if (this.trafficTimerId !== -1) {
      clearInterval(this.trafficTimerId);
    }
    this.trafficTimerId = setInterval(() => {
      if (!tizlinkNative.isRunning()) {
        return;
      }
      try {
        const raw: string = tizlinkNative.getTraffic();
        const stats = JSON.parse(raw) as TrafficStats;
        this.publishStatus(
          'connected',
          '',
          stats.up || 0,
          stats.down || 0,
          stats.upTotal || 0,
          stats.downTotal || 0
        );
      } catch (_e) {
        // ignore parse errors
      }
    }, 1000);
  }

  private publishStatus(
    state: string,
    error: string,
    up: number,
    down: number,
    upTotal: number,
    downTotal: number
  ): void {
    const params: Record<string, Object> = {
      'state': state,
      'error': error,
      'up': up,
      'down': down,
      'upTotal': upTotal,
      'downTotal': downTotal
    };
    const options: commonEventManager.CommonEventPublishData = {
      parameters: params
    };
    commonEventManager.publish(VPN_STATUS_EVENT, options, () => {});
  }
}
