import {
  AppSettings,
  formatBytes,
  formatSpeed,
  ProxyNode,
  RoutingMode,
  TrafficStats,
  VpnState
} from '../model/Models';
import { I18n } from '../model/I18n';
import { Theme } from './Theme';

@Component
export struct ConnectTab {
  @Prop vpnState: VpnState = 'disconnected';
  @Prop traffic: TrafficStats = { up: 0, down: 0, upTotal: 0, downTotal: 0 };
  @Prop selectedNode: ProxyNode | null = null;
  @Prop nodeCount: number = 0;
  @Prop exitIp: string = '--';
  @Prop checkingIp: boolean = false;
  @Prop isWideLayout: boolean = false;
  @Link settings: AppSettings;

  onToggleConnect: () => void = () => {};
  onOpenNodes: () => void = () => {};
  onOpenLineSelector: () => void = () => {};
  onChangeRoutingMode: (mode: RoutingMode) => void = () => {};
  onCheckExitIp: () => void = () => {};

  private getLineRegionName(): string {
    if (this.settings.relayRegion === 'global') {
      return I18n.t('国际线路', 'Global Line');
    }
    if (this.settings.relayRegion === 'auto') {
      return I18n.t('自动匹配线路', 'Auto Line');
    }
    return I18n.t('国内线路', 'Domestic Line');
  }

  private getStatusDotColor(): string {
    if (this.vpnState === 'connected') {
      return Theme.ACCENT_MINT;
    }
    if (this.vpnState === 'connecting' || this.vpnState === 'disconnecting') {
      return Theme.ACCENT_AMBER;
    }
    return Theme.TEXT_SECONDARY;
  }

  private getButtonLabel(): string {
    if (this.vpnState === 'connected') {
      return I18n.t('断开', 'Disconnect');
    }
    if (this.vpnState === 'connecting') {
      return I18n.t('连接中...', 'Connecting...');
    }
    if (this.vpnState === 'disconnecting') {
      return I18n.t('断开中...', 'Disconnecting...');
    }
    return I18n.t('连接', 'Connect');
  }

  private getStatusCaption(): string {
    const nodeLabel: string = this.selectedNode
      ? this.selectedNode.name
      : I18n.t('自动选择最优节点', 'Auto Best Node');
    if (this.vpnState === 'connected') {
      return `${I18n.t('已连接', 'Connected')}  ${nodeLabel}`;
    }
    if (this.vpnState === 'connecting') {
      return `${I18n.t('正在建立安全隧道', 'Establishing tunnel')} · ${nodeLabel}`;
    }
    return I18n.t('未连接', 'Disconnected');
  }

  build() {
    Scroll() {
      Column({ space: 20 }) {
        // Hero Connect Section with Ambient Glow
        Stack({ alignContent: Alignment.Center }) {
          // Soft Neon Halo behind connect button
          Column()
            .width(240)
            .height(240)
            .borderRadius(120)
            .backgroundColor(this.vpnState === 'connected' ? '#265EEAD4' : '#1E94A3B8')
            .blur(60)

          Column({ space: 18 }) {
            // Pill Connect Button (exact Flux/TizLink design)
            Row({ space: 14 }) {
              Text(this.vpnState === 'connected' ? '🔌' : '⏻')
                .fontSize(20)
                .fontColor(Theme.TEXT_PRIMARY)
              Text(this.getButtonLabel())
                .fontSize(19)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TEXT_PRIMARY)
              Blank()
              Circle()
                .width(10)
                .height(10)
                .fill(this.getStatusDotColor())
                .shadow({
                  radius: this.vpnState === 'connected' ? 12 : 4,
                  color: this.getStatusDotColor()
                })
            }
            .width(248)
            .height(74)
            .padding({ left: 32, right: 26 })
            .borderRadius(37)
            .linearGradient({
              angle: 135,
              colors: this.vpnState === 'connected'
                ? [['#25343B', 0.0], ['#1B222C', 1.0]]
                : [['#2A2F3B', 0.0], ['#1A1D26', 1.0]]
            })
            .border({
              width: 1.2,
              color: this.vpnState === 'connected' ? '#555EEAD4' : Theme.BORDER_LIGHT
            })
            .shadow({
              radius: this.vpnState === 'connected' ? 36 : 24,
              color: this.vpnState === 'connected' ? '#405EEAD4' : '#33FFFFFF',
              offsetY: 0
            })
            .onClick(() => {
              this.onToggleConnect();
            })

            Text(this.getStatusCaption())
              .fontSize(15)
              .fontColor(this.vpnState === 'connected' ? Theme.TEXT_PRIMARY : Theme.TEXT_SECONDARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 16, right: 16 })
          }
        }
        .width('100%')
        .height(210)
        .margin({ top: 10 })

        // Current Node Selector Card
        Row({ space: 12 }) {
          Column() {
            Text(this.selectedNode ? this.selectedNode.countryCode : 'AUTO')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.ACCENT_MINT)
          }
          .width(42)
          .height(42)
          .borderRadius(12)
          .backgroundColor('#1A2630')
          .justifyContent(FlexAlign.Center)

          Column({ space: 3 }) {
            Text(this.selectedNode ? this.selectedNode.name : I18n.t('自动选择最优节点', 'Auto Select Best Node'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_PRIMARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(
              this.selectedNode
                ? `${this.selectedNode.type.toUpperCase()} · ${this.selectedNode.regionLabel}`
                : I18n.t(`共 ${this.nodeCount} 个可用节点`, `${this.nodeCount} nodes available`)
            )
              .fontSize(12)
              .fontColor(Theme.TEXT_SECONDARY)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          if (this.selectedNode && this.selectedNode.latencyMs > 0) {
            Text(`${this.selectedNode.latencyMs} ms`)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(
                this.selectedNode.latencyMs < 150
                  ? Theme.ACCENT_GREEN
                  : this.selectedNode.latencyMs < 400
                    ? Theme.ACCENT_AMBER
                    : Theme.ACCENT_RED
              )
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor(Theme.INPUT_BG)
              .borderRadius(8)
          }

          Text('›')
            .fontSize(20)
            .fontColor(Theme.TEXT_SECONDARY)
        }
        .width('100%')
        .padding({ left: 14, right: 16, top: 12, bottom: 12 })
        .backgroundColor(Theme.SURFACE)
        .borderRadius(18)
        .border({ width: 1, color: Theme.BORDER })
        .onClick(() => {
          this.onOpenNodes();
        })

        // Line Selection Card (Domestic / Global / API Lines)
        Row({ space: 12 }) {
          Column() {
            Text('📡')
              .fontSize(16)
          }
          .width(42)
          .height(42)
          .borderRadius(12)
          .backgroundColor('#1A2233')
          .justifyContent(FlexAlign.Center)

          Column({ space: 3 }) {
            Text(I18n.t('线路选择', 'Line Selection'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_PRIMARY)
            Text(
              this.settings.relayRegion === 'global'
                ? I18n.t('当前：国际线路 · 适用于海外地区', 'Active: Global Line')
                : this.settings.relayRegion === 'auto'
                  ? I18n.t('当前：自动匹配 · 按地区智能接入', 'Active: Auto Region')
                  : I18n.t('当前：国内线路 · 中国大陆优化接入', 'Active: Domestic Line (CN)')
            )
              .fontSize(12)
              .fontColor(Theme.TEXT_SECONDARY)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Text(this.getLineRegionName())
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.ACCENT_MINT)
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .backgroundColor('#162B2E')
            .borderRadius(8)

          Text('›')
            .fontSize(20)
            .fontColor(Theme.TEXT_SECONDARY)
        }
        .width('100%')
        .padding({ left: 14, right: 16, top: 12, bottom: 12 })
        .backgroundColor(Theme.SURFACE)
        .borderRadius(18)
        .border({ width: 1, color: Theme.BORDER })
        .onClick(() => {
          this.onOpenLineSelector();
        })

        // Routing Mode Switcher (Smart Rule vs Global)
        Row({ space: 8 }) {
          this.buildRoutingPill(
            'rule',
            I18n.t('智能分流', 'Smart Rule'),
            I18n.t('国内直连 · 海外加速', 'CN Direct · Proxy Abroad')
          )
          this.buildRoutingPill(
            'global',
            I18n.t('全局代理', 'Global Proxy'),
            I18n.t('全部流量加密转发', 'All Traffic Encrypted')
          )
        }
        .width('100%')

        // Live Traffic & Exit IP Card
        Column({ space: 12 }) {
          Row() {
            Column({ space: 4 }) {
              Text(I18n.t('实时下行', 'Download'))
                .fontSize(11)
                .fontColor(Theme.TEXT_MUTED)
              Text(formatSpeed(this.traffic.down))
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.ACCENT_MINT)
              Text(`${I18n.t('累计', 'Total')} ${formatBytes(this.traffic.downTotal)}`)
                .fontSize(11)
                .fontColor(Theme.TEXT_SECONDARY)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Divider()
              .vertical(true)
              .height(38)
              .color(Theme.BORDER)
              .margin({ left: 8, right: 12 })

            Column({ space: 4 }) {
              Text(I18n.t('实时上行', 'Upload'))
                .fontSize(11)
                .fontColor(Theme.TEXT_MUTED)
              Text(formatSpeed(this.traffic.up))
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.ACCENT_BLUE)
              Text(`${I18n.t('累计', 'Total')} ${formatBytes(this.traffic.upTotal)}`)
                .fontSize(11)
                .fontColor(Theme.TEXT_SECONDARY)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')

          Divider().color(Theme.BORDER)

          Row() {
            Text(I18n.t('出口 IP', 'Exit IP'))
              .fontSize(13)
              .fontColor(Theme.TEXT_SECONDARY)
            Blank()
            Text(this.checkingIp ? I18n.t('检测中...', 'Checking...') : this.exitIp)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_PRIMARY)
              .margin({ right: 10 })
            Text(I18n.t('检测', 'Check'))
              .fontSize(12)
              .fontColor(Theme.ACCENT_MINT)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor('#182A2E')
              .borderRadius(8)
              .onClick(() => {
                this.onCheckExitIp();
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Theme.SURFACE)
        .borderRadius(18)
        .border({ width: 1, color: Theme.BORDER })

        // 4 Feature Cards (exact match to APK screenshot 4 & 6)
        GridRow({
          columns: this.isWideLayout ? 4 : 2,
          gutter: { x: 12, y: 12 }
        }) {
          GridCol() {
            this.buildFeatureCard('✳', I18n.t('IXP 接入', 'IXP Access'), I18n.t('极速分流', 'Smart Routing'))
          }
          GridCol() {
            this.buildFeatureCard('⚡', I18n.t('高速稳定', 'High Speed'), I18n.t('4K 秒开', '4K Instant'))
          }
          GridCol() {
            this.buildFeatureCard('🛡', I18n.t('安全日志', 'Zero Logs'), I18n.t('隐私保护', 'Privacy First'))
          }
          GridCol() {
            this.buildFeatureCard('🔒', I18n.t('强力加密', 'Encryption'), 'AEGIS / AES-256')
          }
        }
        .width('100%')
        .margin({ bottom: 24 })
      }
      .width('100%')
      .constraintSize({ maxWidth: 820 })
      .padding({ left: 18, right: 18, top: 6, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildRoutingPill(mode: RoutingMode, title: string, subtitle: string) {
    Column({ space: 3 }) {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.settings.routingMode === mode ? Theme.TEXT_PRIMARY : Theme.TEXT_SECONDARY)
      Text(subtitle)
        .fontSize(11)
        .fontColor(this.settings.routingMode === mode ? Theme.ACCENT_MINT : Theme.TEXT_MUTED)
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 12, left: 12, right: 12 })
    .backgroundColor(this.settings.routingMode === mode ? Theme.SURFACE_ELEVATED : Theme.SURFACE)
    .borderRadius(16)
    .border({
      width: 1,
      color: this.settings.routingMode === mode ? '#665EEAD4' : Theme.BORDER
    })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onChangeRoutingMode(mode);
    })
  }

  @Builder
  private buildFeatureCard(icon: string, title: string, subtitle: string) {
    Row({ space: 12 }) {
      Column() {
        Text(icon)
          .fontSize(16)
          .fontColor(Theme.TEXT_PRIMARY)
      }
      .width(38)
      .height(38)
      .borderRadius(11)
      .backgroundColor(Theme.SURFACE_ELEVATED)
      .justifyContent(FlexAlign.Center)

      Column({ space: 2 }) {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_PRIMARY)
        Text(subtitle)
          .fontSize(11)
          .fontColor(Theme.TEXT_SECONDARY)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 14, bottom: 14 })
    .backgroundColor(Theme.SURFACE)
    .borderRadius(16)
    .border({ width: 1, color: Theme.BORDER })
  }
}
