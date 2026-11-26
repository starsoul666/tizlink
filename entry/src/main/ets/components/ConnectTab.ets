import {
  AppSettings,
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
  @Prop isWideLayout: boolean = false;
  @Link settings: AppSettings;

  onToggleConnect: () => void = () => {};
  onOpenNodes: () => void = () => {};
  onOpenLineSelector: () => void = () => {};
  onChangeRoutingMode: (mode: RoutingMode) => void = () => {};

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
      : I18n.t('自动选择', 'Auto');
    if (this.vpnState === 'connected') {
      return `${I18n.t('已连接', 'Connected')} ${nodeLabel}`;
    }
    if (this.vpnState === 'connecting') {
      return `${I18n.t('正在连接', 'Connecting')} ${nodeLabel}...`;
    }
    return I18n.t('未连接', 'Disconnected');
  }

  private getLineRegionLabel(): string {
    if (this.settings.relayRegion === 'global') {
      return I18n.t('国际线路', 'Global');
    }
    if (this.settings.relayRegion === 'auto') {
      return I18n.t('自动线路', 'Auto');
    }
    return I18n.t('国内线路', 'Domestic');
  }

  build() {
    Column() {
      // Upper Center Area: Glow + Hero Pill Connect Button + Status Text (exact match to APK 4.png & 6.png)
      Column() {
        Stack({ alignContent: Alignment.Center }) {
          // Soft Ambient Halo
          Column()
            .width(260)
            .height(260)
            .borderRadius(130)
            .backgroundColor(this.vpnState === 'connected' ? '#285EEAD4' : '#26CBD5E1')
            .blur(68)

          // Hero Connect Pill Button
          Row({ space: 14 }) {
            Text(this.vpnState === 'connected' ? '🔌' : '⏻')
              .fontSize(20)
              .fontColor(Theme.TEXT_PRIMARY)
            Text(this.getButtonLabel())
              .fontSize(20)
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
          .width(256)
          .height(78)
          .padding({ left: 36, right: 28 })
          .borderRadius(39)
          .linearGradient({
            angle: 135,
            colors: this.vpnState === 'connected'
              ? [['#27343D', 0.0], ['#1B2028', 1.0]]
              : [['#2D323E', 0.0], ['#1B1F28', 1.0]]
          })
          .border({
            width: 1.2,
            color: this.vpnState === 'connected' ? '#555EEAD4' : Theme.BORDER_LIGHT
          })
          .shadow({
            radius: this.vpnState === 'connected' ? 40 : 28,
            color: this.vpnState === 'connected' ? '#405EEAD4' : '#38FFFFFF',
            offsetY: 0
          })
          .onClick(() => {
            this.onToggleConnect();
          })
        }
        .width('100%')
        .height(200)

        // Status Line (clickable to pick node)
        Text(this.getStatusCaption())
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.vpnState === 'connected' ? Theme.TEXT_PRIMARY : Theme.TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
          .onClick(() => {
            this.onOpenNodes();
          })

        // Compact Mode & Line Pills (Rule/Global + Domestic/Global line)
        Row({ space: 10 }) {
          Row({ space: 6 }) {
            Text(this.settings.routingMode === 'rule' ? I18n.t('智能分流', 'Rule') : I18n.t('全局模式', 'Global'))
              .fontSize(12)
              .fontColor(Theme.TEXT_SECONDARY)
            Text('⇄')
              .fontSize(11)
              .fontColor(Theme.TEXT_MUTED)
          }
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(Theme.SURFACE)
          .borderRadius(14)
          .border({ width: 1, color: Theme.BORDER })
          .onClick(() => {
            const next: RoutingMode = this.settings.routingMode === 'rule' ? 'global' : 'rule';
            this.onChangeRoutingMode(next);
          })

          Row({ space: 6 }) {
            Circle()
              .width(6)
              .height(6)
              .fill(Theme.ACCENT_MINT)
            Text(this.getLineRegionLabel())
              .fontSize(12)
              .fontColor(Theme.TEXT_SECONDARY)
            Text('▾')
              .fontSize(10)
              .fontColor(Theme.TEXT_MUTED)
          }
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(Theme.SURFACE)
          .borderRadius(14)
          .border({ width: 1, color: Theme.BORDER })
          .onClick(() => {
            this.onOpenLineSelector();
          })
        }
        .margin({ top: 18 })
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      // Bottom 4 Feature Cards (exact match to APK 4.png 2x2 & 6.png 4x1)
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
          this.buildFeatureCard('🔒', I18n.t('强力加密', 'Encryption'), 'AES-256')
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 820 })
      .padding({ left: 20, right: 20, bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
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
    .padding({ left: 14, right: 14, top: 15, bottom: 15 })
    .backgroundColor(Theme.SURFACE)
    .borderRadius(16)
    .border({ width: 1, color: Theme.BORDER })
  }
}
