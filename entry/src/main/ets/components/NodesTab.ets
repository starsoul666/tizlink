import { ProxyNode } from '../model/Models';
import { I18n } from '../model/I18n';
import { Theme } from './Theme';

@Component
export struct NodesTab {
  @Link nodes: ProxyNode[];
  @Link selectedNodeId: string;
  @Prop refreshing: boolean = false;
  @Prop testingLatency: boolean = false;

  onSelectNode: (nodeId: string) => void = () => {};
  onRefreshSubscription: () => void = () => {};
  onTestAllLatency: () => void = () => {};
  onTestSingleLatency: (node: ProxyNode) => void = () => {};
  onClose: () => void = () => {};

  private getLatencyText(ms: number): string {
    if (ms === -1) {
      return I18n.t('测速', 'Ping');
    }
    if (ms === -2) {
      return I18n.t('超时', 'Timeout');
    }
    return `${ms} ms`;
  }

  private getLatencyColor(ms: number): string {
    if (ms === -1) {
      return Theme.TEXT_SECONDARY;
    }
    if (ms === -2) {
      return Theme.ACCENT_RED;
    }
    if (ms < 150) {
      return Theme.ACCENT_GREEN;
    }
    if (ms < 400) {
      return Theme.ACCENT_AMBER;
    }
    return Theme.ACCENT_RED;
  }

  build() {
    Column({ space: 12 }) {
      // Header Bar (matching APK Node Selector drawer/page)
      Row({ space: 8 }) {
        Text('‹')
          .fontSize(28)
          .fontColor(Theme.TEXT_PRIMARY)
          .width(34)
          .height(34)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onClose();
          })

        Column({ space: 2 }) {
          Text(I18n.t('选择节点', 'Select Node'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT_PRIMARY)
          Text(I18n.t(`共 ${this.nodes.length} 个节点`, `${this.nodes.length} nodes`))
            .fontSize(11)
            .fontColor(Theme.TEXT_SECONDARY)
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        Button(this.testingLatency ? I18n.t('测速中', 'Testing') : I18n.t('测延迟', 'Ping'))
          .height(34)
          .fontSize(12)
          .fontColor(Theme.ACCENT_MINT)
          .backgroundColor('#16292D')
          .borderRadius(10)
          .enabled(!this.testingLatency && this.nodes.length > 0)
          .onClick(() => {
            this.onTestAllLatency();
          })

        Button(this.refreshing ? I18n.t('更新中', 'Syncing') : I18n.t('更新订阅', 'Sync'))
          .height(34)
          .fontSize(12)
          .fontColor(Theme.PRIMARY_BTN_TEXT)
          .backgroundColor(Theme.PRIMARY_BTN_BG)
          .borderRadius(10)
          .enabled(!this.refreshing)
          .onClick(() => {
            this.onRefreshSubscription();
          })
      }
      .width('100%')
      .padding({ left: 10, right: 18, top: 10, bottom: 4 })

      // Auto-select Best Node Card (exact match to APK tip)
      Row({ space: 12 }) {
        Column() {
          Text('⚡')
            .fontSize(16)
            .fontColor(Theme.ACCENT_MINT)
        }
        .width(38)
        .height(38)
        .borderRadius(10)
        .backgroundColor('#162B2E')
        .justifyContent(FlexAlign.Center)

        Column({ space: 3 }) {
          Text(I18n.t('自动选择最佳可用节点', 'Auto Select Best Node'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT_PRIMARY)
          Text(I18n.t('默认自动选择最优节点，无需手动设置。仅在当前节点无法连接时切换。', 'Auto-selects the best node by default.'))
            .fontSize(11)
            .fontColor(Theme.TEXT_SECONDARY)
            .maxLines(2)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.selectedNodeId.length === 0) {
          Text('✓')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.ACCENT_MINT)
        }
      }
      .width('92%')
      .padding({ left: 14, right: 16, top: 12, bottom: 12 })
      .backgroundColor(this.selectedNodeId.length === 0 ? Theme.SURFACE_ELEVATED : Theme.SURFACE)
      .borderRadius(16)
      .border({
        width: 1,
        color: this.selectedNodeId.length === 0 ? '#665EEAD4' : Theme.BORDER
      })
      .onClick(() => {
        this.onSelectNode('');
        this.onClose();
      })

      // Node List
      if (this.nodes.length === 0) {
        Column({ space: 12 }) {
          Text('🌐')
            .fontSize(38)
          Text(I18n.t('暂无可用节点', 'No Nodes Available'))
            .fontSize(16)
            .fontColor(Theme.TEXT_PRIMARY)
          Text(I18n.t('请点击右上角「更新订阅」重新拉取节点', 'Tap Sync to fetch nodes'))
            .fontSize(13)
            .fontColor(Theme.TEXT_SECONDARY)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 10 }) {
          ForEach(this.nodes, (node: ProxyNode) => {
            ListItem() {
              Row({ space: 12 }) {
                Column() {
                  Text(node.countryCode)
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.selectedNodeId === node.id ? Theme.ACCENT_MINT : Theme.TEXT_PRIMARY)
                }
                .width(40)
                .height(40)
                .borderRadius(11)
                .backgroundColor(this.selectedNodeId === node.id ? '#1A2D33' : Theme.SURFACE_ELEVATED)
                .justifyContent(FlexAlign.Center)

                Column({ space: 3 }) {
                  Text(node.name)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.TEXT_PRIMARY)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(node.regionLabel)
                    .fontSize(11)
                    .fontColor(Theme.TEXT_MUTED)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Text(this.getLatencyText(node.latencyMs))
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.getLatencyColor(node.latencyMs))
                  .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                  .backgroundColor(Theme.INPUT_BG)
                  .borderRadius(8)
                  .onClick(() => {
                    this.onTestSingleLatency(node);
                  })

                if (this.selectedNodeId === node.id) {
                  Text('✓')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Theme.ACCENT_MINT)
                }
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .backgroundColor(this.selectedNodeId === node.id ? Theme.SURFACE_ELEVATED : Theme.SURFACE)
              .borderRadius(16)
              .border({
                width: 1,
                color: this.selectedNodeId === node.id ? '#665EEAD4' : Theme.BORDER
              })
              .onClick(() => {
                this.onSelectNode(node.id);
                this.onClose();
              })
            }
          }, (node: ProxyNode) => `${node.id}_${node.latencyMs}`)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 18, right: 18, bottom: 20 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
    .alignItems(HorizontalAlign.Center)
  }
}
