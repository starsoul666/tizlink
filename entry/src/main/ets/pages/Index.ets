import { promptAction } from '@kit.ArkUI';
import {
  APP_VERSION,
  AppSettings,
  AuthSession,
  createDefaultSettings,
  createEmptySubscription,
  PlanItem,
  ProxyNode,
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
import { LineSelectorSheet } from '../components/LineSelectorSheet';
import { NodesTab } from '../components/NodesTab';
import { PlansTab } from '../components/PlansTab';
import { AccountTab } from '../components/AccountTab';

@Entry
@Component
struct Index {
  @State ready: boolean = false;
  @State activeTab: number = 0; // 0: 连接, 1: 订阅, 2: 账户 (exact 3-tab APK layout)
  @State isWideLayout: boolean = false;

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

  @State vpnState: VpnState = 'disconnected';
  @State traffic: TrafficStats = { up: 0, down: 0, upTotal: 0, downTotal: 0 };
  @State refreshingNodes: boolean = false;
  @State refreshingPlans: boolean = false;
  @State testingLatency: boolean = false;
  @State showNodesDrawer: boolean = false;
  @State showLineSheet: boolean = false;

  private vpnListener: VpnUpdateListener = (state: VpnState, traffic: TrafficStats, errorMsg: string) => {
    this.vpnState = state;
    this.traffic = traffic;
    if (errorMsg.length > 0) {
      this.showToast(errorMsg);
    }
  };

  aboutToAppear(): void {
    void this.bootstrap();
  }

  aboutToDisappear(): void {
    VpnManager.getInstance().removeListener(this.vpnListener);
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

  private async handleToggleConnect(): Promise<void> {
    const vpn: VpnManager = VpnManager.getInstance();
    if (this.vpnState === 'connected' || this.vpnState === 'connecting') {
      await vpn.disconnect();
      return;
    }
    if (this.nodes.length === 0) {
      this.showToast(I18n.t('暂无可用节点，请先刷新订阅', 'No nodes available'));
      this.showNodesDrawer = true;
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
        ? I18n.t('自动选择最佳可用节点', 'Auto Best Node')
        : (this.nodes.find((n: ProxyNode) => n.id === nodeId)?.name ?? '');
      this.showToast(I18n.t(`已选择 ${label}`, `Selected ${label}`));
    }
  }

  private async handleRoutingModeChange(mode: RoutingMode): Promise<void> {
    if (this.settings.routingMode === mode) {
      return;
    }
    this.settings.routingMode = mode;
    await StorageService.getInstance().saveSettings(this.settings);
    if (this.vpnState === 'connected') {
      const ok: boolean = await VpnManager.getInstance().switchRoutingMode(mode, this.settings.controllerPort);
      if (!ok) {
        await VpnManager.getInstance().connect(this.nodes, this.selectedNodeId, this.settings);
      }
    }
    this.showToast(
      mode === 'rule'
        ? I18n.t('已切换为智能分流模式', 'Switched to Smart Routing')
        : I18n.t('已切换为全局模式', 'Switched to Global Mode')
    );
  }

  private async handleTestAllLatency(): Promise<void> {
    if (this.testingLatency || this.nodes.length === 0) {
      return;
    }
    this.testingLatency = true;
    const ctrl: MihomoControllerService = MihomoControllerService.getInstance();
    const isConnected: boolean = this.vpnState === 'connected';
    const updated: ProxyNode[] = this.nodes.slice();

    for (let i: number = 0; i < updated.length; i++) {
      const n: ProxyNode = updated[i];
      const ms: number = await ctrl.testNodeLatency(n, isConnected, this.settings.controllerPort);
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
    this.showNodesDrawer = false;
  }

  build() {
    Stack() {
      Column() {
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
              .color(Theme.ACCENT_MINT)
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
        } else if (this.isWideLayout) {
          // Wide Tablet / 2in1 3-tab Sidebar Shell (exact match to APK 6.png - 8.png)
          Row() {
            this.buildSidebarNav()
            Column() {
              this.buildTopHeader()
              Column() {
                this.buildActiveTabContent()
              }
              .layoutWeight(1)
              .width('100%')
            }
            .layoutWeight(1)
            .height('100%')
          }
          .width('100%')
          .height('100%')
          .backgroundColor(Theme.BG)
        } else {
          // Mobile 3-tab Bottom Pill Shell (exact match to APK 4.png - 5.png)
          Column() {
            this.buildTopHeader()
            Column() {
              this.buildActiveTabContent()
            }
            .layoutWeight(1)
            .width('100%')

            this.buildBottomPillNav()
          }
          .width('100%')
          .height('100%')
          .backgroundColor(Theme.BG)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.BG)
      .onAreaChange((_oldVal: Area, newVal: Area) => {
        const w: number = Number(newVal.width) || 0;
        this.isWideLayout = w >= 720;
      })

      // Full-screen Node Selection Page triggered from top-right server icon (matching APK)
      if (this.auth.loggedIn && this.showNodesDrawer) {
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
          },
          onClose: () => {
            this.showNodesDrawer = false;
          }
        })
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
  private buildTopHeader() {
    Row({ space: 10 }) {
      if (!this.isWideLayout) {
        Image($r('app.media.app_icon'))
          .width(28)
          .height(28)
          .borderRadius(7)
        Text('TizLink')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
      }
      Blank()
      // Exact APK top-right server stack icon (opens Node Selector)
      Column({ space: 4 }) {
        Row().width(20).height(3).borderRadius(1.5).backgroundColor(Theme.TEXT_PRIMARY)
        Row().width(20).height(3).borderRadius(1.5).backgroundColor(Theme.TEXT_PRIMARY)
        Row().width(20).height(3).borderRadius(1.5).backgroundColor(Theme.TEXT_PRIMARY)
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.showNodesDrawer = true;
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 18, right: 14 })
    .backgroundColor(Theme.NAV_BG)
    .border({ width: { bottom: 1 }, color: Theme.BORDER })
  }

  @Builder
  private buildSidebarNav() {
    Column() {
      Row({ space: 10 }) {
        Image($r('app.media.app_icon'))
          .width(34)
          .height(34)
          .borderRadius(9)
        Text('TizLink')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 20, bottom: 20 })

      Divider().color(Theme.BORDER)

      Column({ space: 8 }) {
        this.buildSidebarItem(0, '⏻', I18n.t('连接控制', 'Connect'))
        this.buildSidebarItem(1, '💎', I18n.t('订阅方案', 'Plans'))
        this.buildSidebarItem(2, '👤', I18n.t('账户信息', 'Account'))
      }
      .width('100%')
      .padding(14)

      Blank()

      Text(`TIZLINK v${APP_VERSION}`)
        .fontSize(11)
        .fontColor(Theme.TEXT_MUTED)
        .margin({ bottom: 18 })
    }
    .width(220)
    .height('100%')
    .backgroundColor(Theme.NAV_BG)
    .border({ width: { right: 1 }, color: Theme.BORDER })
  }

  @Builder
  private buildSidebarItem(index: number, icon: string, label: string) {
    Row({ space: 12 }) {
      Text(icon)
        .fontSize(15)
        .fontColor(this.activeTab === index ? Theme.TEXT_PRIMARY : Theme.TEXT_SECONDARY)
      Text(label)
        .fontSize(14)
        .fontWeight(this.activeTab === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.activeTab === index ? Theme.TEXT_PRIMARY : Theme.TEXT_SECONDARY)
    }
    .width('100%')
    .height(46)
    .padding({ left: 16, right: 16 })
    .borderRadius(14)
    .backgroundColor(this.activeTab === index ? Theme.PILL_ACTIVE_BG : Color.Transparent)
    .onClick(() => {
      this.activeTab = index;
    })
  }

  @Builder
  private buildBottomPillNav() {
    // Exact 3-tab floating dark pill bar (matching APK 4.png & 5.png)
    Row() {
      this.buildBottomTabItem(0, '⊞', I18n.t('连接', 'Connect'))
      this.buildBottomTabItem(1, '◈', I18n.t('订阅', 'Plans'))
      this.buildBottomTabItem(2, '👤', I18n.t('账户', 'Account'))
    }
    .width('86%')
    .height(64)
    .padding({ left: 10, right: 10 })
    .margin({ bottom: 16, top: 6 })
    .backgroundColor(Theme.NAV_BG)
    .borderRadius(32)
    .border({ width: 1, color: Theme.BORDER })
    .justifyContent(FlexAlign.SpaceAround)
  }

  @Builder
  private buildBottomTabItem(index: number, icon: string, label: string) {
    Row({ space: 8 }) {
      Text(icon)
        .fontSize(17)
        .fontColor(this.activeTab === index ? Theme.TEXT_PRIMARY : Theme.TEXT_SECONDARY)
      if (this.activeTab === index) {
        Text(label)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
      }
    }
    .height(46)
    .padding({
      left: this.activeTab === index ? 24 : 18,
      right: this.activeTab === index ? 24 : 18
    })
    .borderRadius(23)
    .backgroundColor(this.activeTab === index ? Theme.PILL_ACTIVE_BG : Color.Transparent)
    .onClick(() => {
      this.activeTab = index;
    })
  }

  @Builder
  private buildActiveTabContent() {
    if (this.activeTab === 0) {
      ConnectTab({
        vpnState: this.vpnState,
        traffic: this.traffic,
        selectedNode: this.getSelectedNode(),
        isWideLayout: this.isWideLayout,
        settings: $settings,
        onToggleConnect: () => {
          void this.handleToggleConnect();
        },
        onOpenNodes: () => {
          this.showNodesDrawer = true;
        },
        onOpenLineSelector: () => {
          this.showLineSheet = true;
        },
        onChangeRoutingMode: (mode: RoutingMode) => {
          void this.handleRoutingModeChange(mode);
        }
      })
    } else if (this.activeTab === 1) {
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
        }
      })
    } else {
      AccountTab({
        vpnState: this.vpnState,
        subscription: this.subscription,
        settings: $settings,
        auth: $auth,
        onRefreshAccount: () => {
          void this.syncAllRemoteData(true);
        },
        onOpenLineSelector: () => {
          this.showLineSheet = true;
        },
        onSettingsChanged: () => {
          this.settings = {
            whmcsApiUrl: this.settings.whmcsApiUrl,
            apiLines: this.settings.apiLines,
            routingMode: this.settings.routingMode,
            relayRegion: this.settings.relayRegion,
            enableIpv6: this.settings.enableIpv6,
            enableFakeIp: this.settings.enableFakeIp,
            mixedPort: this.settings.mixedPort,
            controllerPort: this.settings.controllerPort,
            splitTunnelEnabled: this.settings.splitTunnelEnabled,
            splitTunnelMode: this.settings.splitTunnelMode,
            splitTunnelApps: this.settings.splitTunnelApps,
            chainProxy: this.settings.chainProxy,
            crispWebsiteId: this.settings.crispWebsiteId,
            telegramUrl: this.settings.telegramUrl,
            language: this.settings.language,
            logLevel: this.settings.logLevel
          };
        },
        onLogout: () => {
          void this.handleLogout();
        }
      })
    }
  }
}
