import {
  AppSettings,
  formatBytes,
  formatDate,
  formatDuration,
  formatSpeed,
  getCountryFlag,
  ProxyNode,
  RelayRegion,
  RoutingMode,
  SubscriptionInfo,
  TrafficStats,
  VpnState
} from '../model/Models';
import { I18n } from '../model/I18n';
import { Theme } from './Theme';

@Component
export struct ConnectTab {
  @Prop vpnState: VpnState = 'disconnected';
  @Prop traffic: TrafficStats = { up: 0, down: 0, upTotal: 0, downTotal: 0 };
  @Prop connectedSeconds: number = 0;
  @Prop publicIp: string = '--';
  @Prop subscription: SubscriptionInfo = {
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
  @Prop selectedNode: ProxyNode | null = null;
  @Prop firstNode: ProxyNode | null = null;
  @Prop refreshing: boolean = false;
  @Link settings: AppSettings;

  onToggleConnect: () => void = () => {};
  onOpenNodes: () => void = () => {};
  onRefreshSubscription: () => void = () => {};
  onOpenNotices: () => void = () => {};
  onOpenPlans: () => void = () => {};
  onChangeRoutingMode: (mode: RoutingMode) => void = () => {};
  onChangeRegion: (region: RelayRegion) => void = () => {};

  private getUsedTraffic(): number {
    return (this.subscription.usedUpload || 0) + (this.subscription.usedDownload || 0);
  }

  private getTrafficPercent(): number {
    const total: number = this.subscription.transferEnable || 0;
    if (total <= 0) {
      return 0;
    }
    return Math.min(100, Math.max(2, (this.getUsedTraffic() / total) * 100));
  }

  private getDisplayNode(): ProxyNode | null {
    return this.selectedNode ?? this.firstNode;
  }

  private getStatusLabel(): string {
    if (this.vpnState === 'connected') {
      return I18n.t('已连接', 'Connected');
    }
    if (this.vpnState === 'connecting') {
      return I18n.t('连接中...', 'Connecting...');
    }
    if (this.vpnState === 'disconnecting') {
      return I18n.t('断开中...', 'Disconnecting...');
    }
    return I18n.t('未连接', 'Disconnected');
  }

  build() {
    Scroll() {
      Column() {
        // Top Header: App Icon + TizLink + Notification Bell (exact match to APK Screenshot #1)
        Row({ space: 10 }) {
          Image($r('app.media.app_icon'))
            .width(34)
            .height(34)
            .borderRadius(9)
          Text('TizLink')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT_PRIMARY)
          Blank()
          Column() {
            Text('🔔')
              .fontSize(18)
              .fontColor(Theme.TEXT_PRIMARY)
          }
          .width(40)
          .height(40)
          .borderRadius(12)
          .backgroundColor(Theme.SURFACE_SOFT)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.onOpenNotices();
          })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 10, bottom: 12 })

        // Traffic & Expiry Strip
        Column({ space: 6 }) {
          Row() {
            Text(`${formatBytes(this.getUsedTraffic())} / ${formatBytes(this.subscription.transferEnable)}`)
              .fontSize(13)
              .fontColor(Theme.TEXT_SECONDARY)
            Blank()
            Row({ space: 6 }) {
              Text(this.subscription.expiredAt > 0 ? formatDate(this.subscription.expiredAt) : '--')
                .fontSize(13)
                .fontColor(Theme.TEXT_MUTED)
              Text('↻')
                .fontSize(15)
                .fontColor(Theme.TEXT_SECONDARY)
            }
            .onClick(() => {
              this.onRefreshSubscription();
            })
          }
          .width('100%')

          Progress({ value: this.getTrafficPercent(), total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(6)
            .color(Theme.ACCENT_BLUE)
            .backgroundColor('#EEF2F7')
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 10 })

        // Connection Status Text
        Text(this.getStatusLabel())
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(
            this.vpnState === 'connected'
              ? Theme.ACCENT_TEAL
              : this.vpnState === 'connecting'
                ? Theme.ACCENT_BLUE
                : Theme.TEXT_SECONDARY
          )
          .margin({ top: 10, bottom: 26 })

        // Big Circular Power Button (exact match to APK Screenshot #1)
        Stack({ alignContent: Alignment.Center }) {
          if (this.vpnState === 'connected') {
            Circle()
              .width(172)
              .height(172)
              .fill('#1F2563EB')
          }
          Column() {
            Text('⏻')
              .fontSize(54)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.vpnState === 'connected' ? Color.White : '#6B7280')
          }
          .width(148)
          .height(148)
          .borderRadius(74)
          .linearGradient({
            angle: 135,
            colors: this.vpnState === 'connected'
              ? [['#2563EB', 0.0], ['#0EA593', 1.0]]
              : this.vpnState === 'connecting'
                ? [['#60A5FA', 0.0], ['#3B82F6', 1.0]]
                : [['#D5D9E1', 0.0], ['#C6CBD5', 1.0]]
          })
          .justifyContent(FlexAlign.Center)
          .shadow({
            radius: this.vpnState === 'connected' ? 28 : 16,
            color: this.vpnState === 'connected' ? '#442563EB' : '#1A000000',
            offsetY: 6
          })
          .onClick(() => {
            this.onToggleConnect();
          })
        }
        .width(180)
        .height(180)

        // Elapsed Duration Timer
        Text(formatDuration(this.connectedSeconds))
          .fontSize(19)
          .fontColor(this.vpnState === 'connected' ? Theme.TEXT_PRIMARY : Theme.TEXT_MUTED)
          .letterSpacing(1.5)
          .margin({ top: 16 })

        // Live Speed Row: ↓ 0 B/s   ↑ 0 B/s
        Row({ space: 22 }) {
          Row({ space: 4 }) {
            Text('↓')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.ACCENT_BLUE)
            Text(formatSpeed(this.traffic.down))
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT_PRIMARY)
          }

          Row({ space: 4 }) {
            Text('↑')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.ACCENT_TEAL)
            Text(formatSpeed(this.traffic.up))
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT_PRIMARY)
          }
        }
        .margin({ top: 10 })

        // Public IP Pill Badge
        Row({ space: 5 }) {
          Text('🌐')
            .fontSize(11)
            .fontColor(Theme.TEXT_MUTED)
          Text(this.publicIp)
            .fontSize(12)
            .fontColor(Theme.TEXT_SECONDARY)
        }
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .backgroundColor(Theme.SURFACE_SOFT)
        .borderRadius(12)
        .margin({ top: 10, bottom: 20 })

        // Node Selector Card + Teal Update Subscription Button
        Row({ space: 10 }) {
          Row({ space: 12 }) {
            Column() {
              Text(this.getDisplayNode() ? getCountryFlag(this.getDisplayNode()!.countryCode) : '⚡')
                .fontSize(22)
            }
            .width(40)
            .height(40)
            .borderRadius(20)
            .backgroundColor(Theme.SURFACE)
            .justifyContent(FlexAlign.Center)

            Column({ space: 2 }) {
              Text(
                this.selectedNode
                  ? this.selectedNode.name
                  : (this.firstNode ? this.firstNode.name : I18n.t('自动选择', 'Auto Best'))
              )
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TEXT_PRIMARY)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(
                this.getDisplayNode()
                  ? this.getDisplayNode()!.type.toUpperCase()
                  : 'TROJAN'
              )
                .fontSize(11)
                .fontColor(Theme.TEXT_MUTED)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Text('›')
              .fontSize(22)
              .fontColor(Theme.TEXT_SECONDARY)
          }
          .layoutWeight(1)
          .height(66)
          .padding({ left: 14, right: 14 })
          .backgroundColor(Theme.SURFACE_SOFT)
          .borderRadius(16)
          .border({ width: 1, color: Theme.BORDER })
          .onClick(() => {
            this.onOpenNodes();
          })

          // Teal Update Subscription Button
          Row({ space: 5 }) {
            Text('↻')
              .fontSize(15)
              .fontColor(Color.White)
            Text(this.refreshing ? I18n.t('更新中', 'Sync') : I18n.t('更新订阅', 'Sync'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
          }
          .width(106)
          .height(66)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(Theme.ACCENT_TEAL)
          .borderRadius(16)
          .onClick(() => {
            if (!this.refreshing) {
              this.onRefreshSubscription();
            }
          })
        }
        .width('100%')
        .padding({ left: 20, right: 20 })

        // Proxy Mode & Line Unified Card (exact match to APK Screenshot #1)
        Column() {
          // Row 1: 代理模式 [ 规则 | 全局 ]
          Row() {
            Row({ space: 8 }) {
              Text('⇄')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.ACCENT_PURPLE)
              Text(I18n.t('代理模式', 'Proxy Mode'))
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TEXT_PRIMARY)
              Text('?')
                .fontSize(10)
                .fontColor(Theme.TEXT_MUTED)
                .width(16)
                .height(16)
                .textAlign(TextAlign.Center)
                .borderRadius(8)
                .border({ width: 1, color: Theme.BORDER_LIGHT })
            }
            Blank()
            Row({ space: 2 }) {
              this.buildSegmentOption(
                I18n.t('规则', 'Rule'),
                this.settings.routingMode === 'rule',
                () => this.onChangeRoutingMode('rule')
              )
              this.buildSegmentOption(
                I18n.t('全局', 'Global'),
                this.settings.routingMode === 'global',
                () => this.onChangeRoutingMode('global')
              )
            }
            .padding(3)
            .backgroundColor('#E5E9F1')
            .borderRadius(11)
          }
          .width('100%')
          .height(52)

          Divider().color('#E8ECF3')

          // Row 2: 线路 [ 国内 | 国际 ]
          Row() {
            Row({ space: 8 }) {
              Text('⑂')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.ACCENT_PURPLE)
              Text(I18n.t('线路', 'Line'))
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TEXT_PRIMARY)
            }
            Blank()
            Row({ space: 2 }) {
              this.buildSegmentOption(
                I18n.t('国内', 'CN'),
                this.settings.relayRegion !== 'global',
                () => this.onChangeRegion('cn')
              )
              this.buildSegmentOption(
                I18n.t('国际', 'Global'),
                this.settings.relayRegion === 'global',
                () => this.onChangeRegion('global')
              )
            }
            .padding(3)
            .backgroundColor('#E5E9F1')
            .borderRadius(11)
          }
          .width('100%')
          .height(52)
        }
        .width('calc(100% - 40vp)')
        .padding({ left: 16, right: 14, top: 4, bottom: 4 })
        .margin({ top: 12 })
        .backgroundColor(Theme.SURFACE_SOFT)
        .borderRadius(18)
        .border({ width: 1, color: Theme.BORDER })

        // Purple-Outlined 订阅 Button (exact match to APK Screenshot #1)
        Row({ space: 6 }) {
          Text('🛒')
            .fontSize(15)
          Text(I18n.t('订阅', 'Subscribe'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.ACCENT_PURPLE)
        }
        .width('calc(100% - 40vp)')
        .height(48)
        .margin({ top: 12, bottom: 96 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.SURFACE)
        .borderRadius(14)
        .border({ width: 1.5, color: Theme.ACCENT_PURPLE })
        .onClick(() => {
          this.onOpenPlans();
        })
      }
      .width('100%')
      .constraintSize({ maxWidth: 560 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildSegmentOption(label: string, active: boolean, onClick: () => void) {
    Text(label)
      .fontSize(13)
      .fontWeight(active ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(active ? Theme.ACCENT_BLUE : Theme.TEXT_SECONDARY)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(active ? Theme.SURFACE : Color.Transparent)
      .borderRadius(9)
      .shadow(active ? { radius: 4, color: '#14000000', offsetY: 1 } : { radius: 0, color: Color.Transparent })
      .onClick(onClick)
  }
}
