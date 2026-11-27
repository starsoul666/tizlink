import { promptAction } from '@kit.ArkUI';
import {
  AppSettings,
  AuthSession,
  createDefaultSettings,
  createEmptySubscription,
  formatDate,
  NoticeItem,
  PlanItem,
  ProxyNode,
  RelayRegion,
  RoutingMode,
  SubscriptionInfo,
  TrafficStats,
  VpnState
} from '../model/Models';
import { I18n } from '../model/I18n';
import { StorageService } from '../service/StorageService';
import { ApiService } from '../service/ApiService';
import { MihomoControllerService } from '../service/MihomoControllerService';
import { VpnManager, VpnUpdateListener } from '../service/VpnManager';
import { Theme } from '../components/Theme';
import { AuthView } from '../components/AuthView';
import { ConnectTab } from '../components/ConnectTab';
import { NodesTab } from '../components/NodesTab';
import { AccountTab } from '../components/AccountTab';
import { SettingsTab } from '../components/SettingsTab';
import { PlansTab } from '../components/PlansTab';
import { LineSelectorSheet } from '../components/LineSelectorSheet';

@Entry
@Component
struct Index {
  @State ready: boolean = false;
  @State activeTab: number = 0; // 0: 连接, 1: 节点, 2: 我的, 3: 设置 (exact 4-tab APK layout)

  @State settings: AppSettings = createDefaultSettings();
  @State auth: AuthSession = {
    loggedIn: false,
    email: '',
    token: '',
    authData: '',
    savedPassword: '',
    deviceId: ''
  };
  @State subscription: SubscriptionInfo = createEmptySubscription();
  @State nodes: ProxyNode[] = [];
  @State selectedNodeId: string = '';
  @State plans: PlanItem[] = [];
  @State notices: NoticeItem[] = [];

  @State vpnState: VpnState = 'disconnected';
  @State traffic: TrafficStats = { up: 0, down: 0, upTotal: 0, downTotal: 0 };
  @State connectedSeconds: number = 0;
  @State publicIp: string = '--';
  @State refreshingNodes: boolean = false;
  @State refreshingPlans: boolean = false;
  @State testingLatency: boolean = false;

  @State showPlansOverlay: boolean = false;
  @State showNoticesOverlay: boolean = false;
  @State showLineSheet: boolean = false;

  private durationTimerId: number = -1;

  private vpnListener: VpnUpdateListener = (state: VpnState, traffic: TrafficStats, errorMsg: string) => {
    const prevState: VpnState = this.vpnState;
    this.vpnState = state;
    this.traffic = traffic;
    if (state === 'connected' && prevState !== 'connected') {
      this.startDurationTimer();
      void this.refreshPublicIp();
    } else if (state === 'disconnected') {
      this.stopDurationTimer();
      this.connectedSeconds = 0;
    }
    if (errorMsg.length > 0) {
      this.showToast(errorMsg);
    }
  };

  aboutToAppear(): void {
    void this.bootstrap();
  }

  aboutToDisappear(): void {
    this.stopDurationTimer();
    VpnManager.getInstance().removeListener(this.vpnListener);
  }

  private startDurationTimer(): void {
    this.stopDurationTimer();
    this.connectedSeconds = 0;
    this.durationTimerId = setInterval(() => {
      this.connectedSeconds += 1;
    }, 1000);
  }

  private stopDurationTimer(): void {
    if (this.durationTimerId !== -1) {
      clearInterval(this.durationTimerId);
      this.durationTimerId = -1;
    }
  }

  private async bootstrap(): Promise<void> {
    const storage: StorageService = StorageService.getInstance();
    this.settings = await storage.loadSettings();
    I18n.lang = this.settings.language;
    this.auth = await storage.loadAuth();
    this.subscription = await storage.loadSubscription();
    this.nodes = await storage.loadNodes();
    this.selectedNodeId = await storage.getSelectedNodeId();

    VpnManager.getInstance().addListener(this.vpnListener);
    this.ready = true;

    if (this.auth.loggedIn) {
      void this.syncAllRemoteData(false);
      void this.refreshPublicIp();
    }
  }

  private async refreshPublicIp(): Promise<void> {
    const ip: string = await ApiService.getInstance().fetchExitIp();
    if (ip.length > 0 && ip !== '--') {
      this.publicIp = ip;
    }
  }

  private showToast(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 2200 });
    } catch (_e) {
      // ignore
    }
  }

  private getSelectedNode(): ProxyNode | null {
    if (this.selectedNodeId.length === 0) {
      return null;
    }
    const found: ProxyNode | undefined = this.nodes.find((n: ProxyNode) => n.id === this.selectedNodeId);
    return found ?? null;
  }

  private getFirstNode(): ProxyNode | null {
    return this.nodes.length > 0 ? this.nodes[0] : null;
  }

  private async syncAllRemoteData(showFeedback: boolean): Promise<void> {
    const api: ApiService = ApiService.getInstance();
    const storage: StorageService = StorageService.getInstance();

    this.refreshingNodes = true;
    const syncRes = await api.syncWhmcsSession(this.settings, this.auth);
    if (syncRes.ok && syncRes.data) {
      this.subscription = syncRes.data.subscription;
      await storage.saveSubscription(syncRes.data.subscription);
      if (syncRes.data.nodes.length > 0) {
        this.nodes = syncRes.data.nodes;
        await storage.saveNodes(syncRes.data.nodes);
      }
      if (showFeedback) {
        this.showToast(syncRes.message);
      }
    } else if (showFeedback) {
      this.showToast(syncRes.message);
    }
    this.refreshingNodes = false;
    void this.loadPlans(false);
  }

  private async loadPlans(showFeedback: boolean): Promise<void> {
    this.refreshingPlans = true;
    const res = await ApiService.getInstance().fetchPlans(this.settings, this.auth);
    this.refreshingPlans = false;
    if (res.ok && res.data) {
      this.plans = res.data;
    } else if (showFeedback) {
      this.showToast(res.message);
    }
  }

  private async openNoticesModal(): Promise<void> {
    this.showNoticesOverlay = true;
    const res = await ApiService.getInstance().fetchNotices(this.settings, this.auth);
    if (res.ok && res.data) {
      this.notices = res.data;
    }
  }

  private async handleToggleConnect(): Promise<void> {
    const vpn: VpnManager = VpnManager.getInstance();
    if (this.vpnState === 'connected' || this.vpnState === 'connecting') {
      await vpn.disconnect();
      return;
    }
    if (this.nodes.length === 0) {
      this.showToast(I18n.t('暂无可用节点，请先更新订阅', 'No nodes available'));
      this.activeTab = 1;
      return;
    }
    const err: string = await vpn.connect(this.nodes, this.selectedNodeId, this.settings);
    if (err.length > 0) {
      this.showToast(err);
    }
  }

  private async handleSelectNode(nodeId: string): Promise<void> {
    this.selectedNodeId = nodeId;
    await StorageService.getInstance().setSelectedNodeId(nodeId);

    if (this.vpnState === 'connected') {
      const targetName: string = nodeId.length === 0
        ? 'AUTO'
        : (this.nodes.find((n: ProxyNode) => n.id === nodeId)?.name ?? 'AUTO');
      const ok: boolean = await VpnManager.getInstance().hotSwitchNode(targetName, this.settings.controllerPort);
      if (ok) {
        this.showToast(I18n.t(`已切换至 ${targetName}`, `Switched to ${targetName}`));
      } else {
        this.showToast(I18n.t('正在重新连接至所选节点...', 'Reconnecting...'));
        await VpnManager.getInstance().connect(this.nodes, this.selectedNodeId, this.settings);
      }
    } else {
      const label: string = nodeId.length === 0
        ? I18n.t('自动选择最佳节点', 'Auto Best Node')
        : (this.nodes.find((n: ProxyNode) => n.id === nodeId)?.name ?? '');
      this.showToast(I18n.t(`已选择 ${label}`, `Selected ${label}`));
    }
    this.activeTab = 0;
  }

  private cloneSettings(): AppSettings {
    return {
      whmcsApiUrl: this.settings.whmcsApiUrl,
      apiLines: this.settings.apiLines,
      routingMode: this.settings.routingMode,
      relayRegion: this.settings.relayRegion,
      enableIpv6: this.settings.enableIpv6,
      enableFakeIp: this.settings.enableFakeIp,
      mixedPort: this.settings.mixedPort,
      socksPort: this.settings.socksPort,
      allowLan: this.settings.allowLan,
      controllerPort: this.settings.controllerPort,
      customDns: this.settings.customDns,
      customRules: this.settings.customRules,
      splitTunnelEnabled: this.settings.splitTunnelEnabled,
      splitTunnelMode: this.settings.splitTunnelMode,
      splitTunnelApps: this.settings.splitTunnelApps,
      chainProxy: this.settings.chainProxy,
      crispWebsiteId: this.settings.crispWebsiteId,
      telegramUrl: this.settings.telegramUrl,
      language: this.settings.language,
      logLevel: this.settings.logLevel
    };
  }

  private async handleRoutingModeChange(mode: RoutingMode): Promise<void> {
    if (this.settings.routingMode === mode) {
      return;
    }
    this.settings.routingMode = mode;
    this.settings = this.cloneSettings();
    await StorageService.getInstance().saveSettings(this.settings);
    if (this.vpnState === 'connected') {
      const ok: boolean = await VpnManager.getInstance().switchRoutingMode(mode, this.settings.controllerPort);
      if (!ok) {
        await VpnManager.getInstance().connect(this.nodes, this.selectedNodeId, this.settings);
      }
    }
    this.showToast(
      mode === 'rule'
        ? I18n.t('已切换为规则模式', 'Switched to Rule Mode')
        : I18n.t('已切换为全局模式', 'Switched to Global Mode')
    );
  }

  private async handleRegionChange(region: RelayRegion): Promise<void> {
    if (this.settings.relayRegion === region) {
      return;
    }
    this.settings.relayRegion = region;
    this.settings = this.cloneSettings();
    await StorageService.getInstance().saveSettings(this.settings);
    this.showToast(
      region === 'cn'
        ? I18n.t('已切换为国内线路', 'Switched to Domestic Line')
        : I18n.t('已切换为国际线路', 'Switched to Global Line')
    );
    if (this.vpnState === 'connected') {
      await VpnManager.getInstance().connect(this.nodes, this.selectedNodeId, this.settings);
    }
  }

  private async handleTestAllLatency(): Promise<void> {
    if (this.testingLatency || this.nodes.length === 0) {
      return;
    }
    this.testingLatency = true;
    const ctrl: MihomoControllerService = MihomoControllerService.getInstance();
    const isConnected: boolean = this.vpnState === 'connected';
    const updated: ProxyNode[] = this.nodes.slice();

    // Fast path when VPN is connected: single concurrent Mihomo Go batch test (/group/PROXY/delay)
    if (isConnected) {
      const batchMap: Record<string, number> | null = await ctrl.testGroupDelayViaController(
        this.settings.controllerPort,
        'PROXY',
        3000
      );
      if (batchMap !== null) {
        for (let i: number = 0; i < updated.length; i++) {
          const n: ProxyNode = updated[i];
          const val: number | undefined = batchMap[n.name];
          const ms: number = (typeof val === 'number' && val > 0) ? Math.round(val) : -2;
          updated[i] = {
            id: n.id,
            name: n.name,
            type: n.type,
            server: n.server,
            port: n.port,
            countryCode: n.countryCode,
            regionLabel: n.regionLabel,
            latencyMs: ms,
            rawYamlLines: n.rawYamlLines,
            rawUri: n.rawUri
          };
        }
        this.nodes = updated.slice();
        this.testingLatency = false;
        await StorageService.getInstance().saveNodes(this.nodes);
        return;
      }
    }

    // Disconnected (or fallback): pre-resolve unique hostnames once, then run parallel batches of 8
    const uniqueHosts: Set<string> = new Set<string>();
    for (const n of updated) {
      if (n.server.length > 0) {
        uniqueHosts.add(n.server);
      }
    }
    const resolveTasks: Promise<string>[] = [];
    uniqueHosts.forEach((h: string) => {
      resolveTasks.push(ctrl.resolveHostIpv4(h));
    });
    await Promise.all(resolveTasks);

    const concurrency: number = 8;
    for (let start: number = 0; start < updated.length; start += concurrency) {
      const end: number = Math.min(updated.length, start + concurrency);
      const batchPromises: Promise<void>[] = [];
      for (let idx: number = start; idx < end; idx++) {
        const targetIndex: number = idx;
        const n: ProxyNode = updated[targetIndex];
        batchPromises.push(
          ctrl.testNodeLatency(n, isConnected, this.settings.controllerPort).then((ms: number) => {
            updated[targetIndex] = {
              id: n.id,
              name: n.name,
              type: n.type,
              server: n.server,
              port: n.port,
              countryCode: n.countryCode,
              regionLabel: n.regionLabel,
              latencyMs: ms,
              rawYamlLines: n.rawYamlLines,
              rawUri: n.rawUri
            };
          })
        );
      }
      await Promise.all(batchPromises);
      this.nodes = updated.slice();
    }

    this.testingLatency = false;
    await StorageService.getInstance().saveNodes(this.nodes);
  }

  private async handleTestSingleLatency(node: ProxyNode): Promise<void> {
    const ms: number = await MihomoControllerService.getInstance().testNodeLatency(
      node,
      this.vpnState === 'connected',
      this.settings.controllerPort
    );
    this.nodes = this.nodes.map((n: ProxyNode) => {
      if (n.id !== node.id) {
        return n;
      }
      return {
        id: n.id,
        name: n.name,
        type: n.type,
        server: n.server,
        port: n.port,
        countryCode: n.countryCode,
        regionLabel: n.regionLabel,
        latencyMs: ms,
        rawYamlLines: n.rawYamlLines,
        rawUri: n.rawUri
      };
    });
  }

  private async handleAuthSuccess(subUrl: string): Promise<void> {
    const storage: StorageService = StorageService.getInstance();
    this.subscription = await storage.loadSubscription();
    this.nodes = await storage.loadNodes();
    if (subUrl.length > 0) {
      this.subscription.subscribeUrl = subUrl;
    }
    void this.refreshPublicIp();
    if (this.nodes.length > 0) {
      void this.loadPlans(false);
    } else {
      void this.syncAllRemoteData(true);
    }
  }

  private async handleLineSaved(regionChanged: boolean, apiChanged: boolean): Promise<void> {
    if (apiChanged) {
      await this.syncAllRemoteData(true);
    } else if (regionChanged && this.vpnState === 'connected') {
      this.showToast(I18n.t('线路已切换，正在重新连接...', 'Reconnecting with new line...'));
      await VpnManager.getInstance().connect(this.nodes, this.selectedNodeId, this.settings);
    }
  }

  private async handleLogout(): Promise<void> {
    await VpnManager.getInstance().disconnect();
    await StorageService.getInstance().clearAuth();
    this.auth = await StorageService.getInstance().loadAuth();
    this.activeTab = 0;
    this.showPlansOverlay = false;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (!this.ready) {
        Column({ space: 14 }) {
          Image($r('app.media.app_icon'))
            .width(72)
            .height(72)
            .borderRadius(18)
          Text('TizLink')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT_PRIMARY)
          LoadingProgress()
            .width(30)
            .height(30)
            .color(Theme.ACCENT_BLUE)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.BG)
      } else if (!this.auth.loggedIn) {
        AuthView({
          settings: $settings,
          auth: $auth,
          onAuthSuccess: (subUrl: string) => {
            void this.handleAuthSuccess(subUrl);
          }
        })
      } else {
        // Main 4-Tab Content Area (full height, content scrolls behind floating pill nav like real APK!)
        Column() {
          if (this.activeTab === 0) {
            ConnectTab({
              vpnState: this.vpnState,
              traffic: this.traffic,
              connectedSeconds: this.connectedSeconds,
              publicIp: this.publicIp,
              subscription: this.subscription,
              selectedNode: this.getSelectedNode(),
              firstNode: this.getFirstNode(),
              refreshing: this.refreshingNodes,
              settings: $settings,
              onToggleConnect: () => {
                void this.handleToggleConnect();
              },
              onOpenNodes: () => {
                this.activeTab = 1;
              },
              onRefreshSubscription: () => {
                void this.syncAllRemoteData(true);
              },
              onOpenNotices: () => {
                void this.openNoticesModal();
              },
              onOpenPlans: () => {
                this.showPlansOverlay = true;
                if (this.plans.length === 0) {
                  void this.loadPlans(false);
                }
              },
              onChangeRoutingMode: (mode: RoutingMode) => {
                void this.handleRoutingModeChange(mode);
              },
              onChangeRegion: (region: RelayRegion) => {
                void this.handleRegionChange(region);
              }
            })
          } else if (this.activeTab === 1) {
            NodesTab({
              nodes: $nodes,
              selectedNodeId: $selectedNodeId,
              refreshing: this.refreshingNodes,
              testingLatency: this.testingLatency,
              onSelectNode: (id: string) => {
                void this.handleSelectNode(id);
              },
              onRefreshSubscription: () => {
                void this.syncAllRemoteData(true);
              },
              onTestAllLatency: () => {
                void this.handleTestAllLatency();
              },
              onTestSingleLatency: (node: ProxyNode) => {
                void this.handleTestSingleLatency(node);
              }
            })
          } else if (this.activeTab === 2) {
            AccountTab({
              vpnState: this.vpnState,
              subscription: this.subscription,
              settings: $settings,
              auth: $auth,
              onRefreshAccount: () => {
                void this.syncAllRemoteData(true);
              },
              onOpenPlans: () => {
                this.showPlansOverlay = true;
                if (this.plans.length === 0) {
                  void this.loadPlans(false);
                }
              },
              onLogout: () => {
                void this.handleLogout();
              }
            })
          } else {
            SettingsTab({
              settings: $settings,
              onOpenLineSelector: () => {
                this.showLineSheet = true;
              },
              onSettingsChanged: () => {
                this.settings = this.cloneSettings();
              }
            })
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.BG)

        // Floating White 4-Tab Bottom Pill Navigation Bar (exact match to APK Screenshots #1, #2, #4)
        this.buildFloatingBottomNav()
      }

      // Full-screen Plans Overlay (triggered from 🛒 订阅 / 续费订阅 / 升级套餐)
      if (this.auth.loggedIn && this.showPlansOverlay) {
        PlansTab({
          plans: this.plans,
          loading: this.refreshingPlans,
          settings: this.settings,
          auth: this.auth,
          onRefreshPlans: () => {
            void this.loadPlans(true);
          },
          onOrderCompleted: () => {
            void this.syncAllRemoteData(true);
          },
          onClose: () => {
            this.showPlansOverlay = false;
          }
        })
      }

      // Announcements Modal (triggered from top-right 🔔 bell on ConnectTab)
      if (this.auth.loggedIn && this.showNoticesOverlay) {
        Column() {
          Column({ space: 12 }) {
            Row() {
              Text(I18n.t('系统公告', 'Announcements'))
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TEXT_PRIMARY)
              Blank()
              Text('✕')
                .fontSize(18)
                .fontColor(Theme.TEXT_SECONDARY)
                .onClick(() => {
                  this.showNoticesOverlay = false;
                })
            }
            .width('100%')

            if (this.notices.length === 0) {
              Text(I18n.t('暂无最新公告', 'No announcements'))
                .fontSize(14)
                .fontColor(Theme.TEXT_SECONDARY)
                .margin({ top: 24, bottom: 24 })
            } else {
              Scroll() {
                Column({ space: 10 }) {
                  ForEach(this.notices, (n: NoticeItem) => {
                    Column({ space: 6 }) {
                      Row() {
                        Text(n.title).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY).layoutWeight(1)
                        Text(formatDate(n.createdAt)).fontSize(11).fontColor(Theme.TEXT_MUTED)
                      }.width('100%')
                      Text(n.content.replace(/<[^>]+>/g, '').trim())
                        .fontSize(13)
                        .fontColor(Theme.TEXT_SECONDARY)
                        .lineHeight(20)
                    }
                    .width('100%')
                    .padding(14)
                    .backgroundColor(Theme.SURFACE_SOFT)
                    .borderRadius(14)
                    .alignItems(HorizontalAlign.Start)
                  }, (n: NoticeItem) => `${n.id}_${n.title}`)
                }
              }
              .constraintSize({ maxHeight: 360 })
            }
          }
          .width('90%')
          .constraintSize({ maxWidth: 440 })
          .padding(20)
          .backgroundColor(Theme.SURFACE)
          .borderRadius(22)
          .shadow({ radius: 24, color: '#26000000', offsetY: 8 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .justifyContent(FlexAlign.Center)
      }

      if (this.showLineSheet) {
        LineSelectorSheet({
          settings: $settings,
          onClose: () => {
            this.showLineSheet = false;
          },
          onSaved: (regionChanged: boolean, apiChanged: boolean) => {
            void this.handleLineSaved(regionChanged, apiChanged);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }

  @Builder
  private buildFloatingBottomNav() {
    Row() {
      this.buildBottomTabItem(0, '⊞', I18n.t('连接', 'Connect'), Theme.ACCENT_BLUE_SOFT, Theme.ACCENT_BLUE)
      this.buildBottomTabItem(1, '❖', I18n.t('节点', 'Nodes'), Theme.ACCENT_BLUE_SOFT, Theme.ACCENT_BLUE)
      this.buildBottomTabItem(2, '👤', I18n.t('我的', 'Mine'), Theme.ACCENT_PURPLE_SOFT, Theme.ACCENT_PURPLE)
      this.buildBottomTabItem(3, '⚙', I18n.t('设置', 'Settings'), Theme.ACCENT_TEAL_SOFT, Theme.ACCENT_TEAL)
    }
    .width('90%')
    .constraintSize({ maxWidth: 460 })
    .height(66)
    .padding({ left: 10, right: 10 })
    .margin({ bottom: 16 })
    .backgroundColor(Theme.NAV_BG)
    .borderRadius(33)
    .border({ width: 1, color: '#EEF0F5' })
    .shadow({ radius: 22, color: Theme.SHADOW_NAV, offsetY: 6 })
    .justifyContent(FlexAlign.SpaceAround)
  }

  @Builder
  private buildBottomTabItem(index: number, icon: string, label: string, activeBg: string, activeColor: string) {
    Row({ space: 6 }) {
      Text(icon)
        .fontSize(18)
        .fontColor(this.activeTab === index ? activeColor : Theme.TEXT_SECONDARY)
      if (this.activeTab === index) {
        Text(label)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(activeColor)
      }
    }
    .height(46)
    .padding({
      left: this.activeTab === index ? 18 : 14,
      right: this.activeTab === index ? 18 : 14
    })
    .borderRadius(23)
    .backgroundColor(this.activeTab === index ? activeBg : Color.Transparent)
    .onClick(() => {
      this.activeTab = index;
    })
  }
}
