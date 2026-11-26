import { promptAction } from '@kit.ArkUI';
import { ProxyNode } from '../model/Models';
import { I18n } from '../model/I18n';
import { SubscriptionParser } from '../service/SubscriptionParser';
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
  onImportManualNodes: (imported: ProxyNode[], subUrl: string) => void = () => {};

  @State searchKeyword: string = '';
  @State showImportPanel: boolean = false;
  @State importText: string = '';

  private getFilteredNodes(): ProxyNode[] {
    const kw: string = this.searchKeyword.trim().toLowerCase();
    if (kw.length === 0) {
      return this.nodes;
    }
    return this.nodes.filter((n: ProxyNode) =>
      n.name.toLowerCase().includes(kw) ||
      n.countryCode.toLowerCase().includes(kw) ||
      n.regionLabel.toLowerCase().includes(kw) ||
      n.type.toLowerCase().includes(kw)
    );
  }

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

  private handleImport(): void {
    const raw: string = this.importText.trim();
    if (raw.length === 0) {
      promptAction.showToast({ message: I18n.t('请输入订阅链接或节点 URI', 'Enter subscription URL or node URI') });
      return;
    }
    if ((raw.startsWith('http://') || raw.startsWith('https://')) && !raw.includes('\n')) {
      this.showImportPanel = false;
      this.importText = '';
      this.onImportManualNodes([], raw);
      return;
    }
    const parsed: ProxyNode[] = SubscriptionParser.parseSubscription(raw);
    if (parsed.length === 0) {
      promptAction.showToast({ message: I18n.t('未识别到有效节点 (支持 aegis/vless/vmess/trojan/ss/hy2/tuic/YAML)', 'No valid nodes parsed') });
      return;
    }
    this.showImportPanel = false;
    this.importText = '';
    this.onImportManualNodes(parsed, '');
  }

  build() {
    Column({ space: 12 }) {
      // Header + Actions
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(I18n.t('节点列表', 'Proxy Nodes'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT_PRIMARY)
          Text(I18n.t(`共 ${this.nodes.length} 个节点`, `${this.nodes.length} nodes`))
            .fontSize(12)
            .fontColor(Theme.TEXT_SECONDARY)
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        Button(I18n.t('导入', 'Import'))
          .height(34)
          .fontSize(12)
          .fontColor(Theme.TEXT_PRIMARY)
          .backgroundColor(Theme.SURFACE_ELEVATED)
          .borderRadius(10)
          .border({ width: 1, color: Theme.BORDER })
          .onClick(() => {
            this.showImportPanel = !this.showImportPanel;
          })

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

        Button(this.refreshing ? I18n.t('同步中', 'Syncing') : I18n.t('更新', 'Sync'))
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
      .padding({ left: 18, right: 18, top: 8 })

      // Manual Import Drawer
      if (this.showImportPanel) {
        Column({ space: 10 }) {
          Text(I18n.t(
            '粘贴订阅链接 (https://...)、Clash YAML 或节点 URI (aegis:// vless:// vmess:// trojan:// ss:// hy2://)',
            'Paste subscription URL, Clash YAML, or node URIs'
          ))
            .fontSize(12)
            .fontColor(Theme.TEXT_SECONDARY)
          TextArea({
            text: this.importText,
            placeholder: 'https://... 或 aegis://... / vless://... / vmess://...'
          })
            .height(92)
            .fontSize(12)
            .fontColor(Theme.TEXT_PRIMARY)
            .placeholderColor(Theme.TEXT_MUTED)
            .backgroundColor(Theme.INPUT_BG)
            .borderRadius(12)
            .border({ width: 1, color: Theme.BORDER })
            .onChange((v: string) => {
              this.importText = v;
            })
          Row({ space: 10 }) {
            Button(I18n.t('取消', 'Cancel'))
              .layoutWeight(1)
              .height(38)
              .fontSize(13)
              .fontColor(Theme.TEXT_SECONDARY)
              .backgroundColor(Theme.SURFACE_ELEVATED)
              .borderRadius(10)
              .onClick(() => {
                this.showImportPanel = false;
              })
            Button(I18n.t('确认导入', 'Import Now'))
              .layoutWeight(1)
              .height(38)
              .fontSize(13)
              .fontColor(Theme.PRIMARY_BTN_TEXT)
              .backgroundColor(Theme.PRIMARY_BTN_BG)
              .borderRadius(10)
              .onClick(() => {
                this.handleImport();
              })
          }
        }
        .width('100%')
        .padding({ left: 18, right: 18 })
      }

      // Search Bar
      Row({ space: 8 }) {
        Text('🔍')
          .fontSize(14)
          .fontColor(Theme.TEXT_MUTED)
        TextInput({ text: this.searchKeyword, placeholder: I18n.t('搜索国家、节点名或协议...', 'Search nodes...') })
          .fontSize(14)
          .fontColor(Theme.TEXT_PRIMARY)
          .placeholderColor(Theme.TEXT_MUTED)
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .height(38)
          .onChange((v: string) => {
            this.searchKeyword = v;
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14 })
      .margin({ left: 18, right: 18 })
      .height(44)
      .backgroundColor(Theme.SURFACE)
      .borderRadius(14)
      .border({ width: 1, color: Theme.BORDER })

      // Auto-select Best Node Card
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

        Column({ space: 2 }) {
          Text(I18n.t('自动选择最优节点', 'Auto Select Best Node'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT_PRIMARY)
          Text(I18n.t('默认自动测速切换最低延迟线路', 'Automatically switches to the fastest node'))
            .fontSize(11)
            .fontColor(Theme.TEXT_SECONDARY)
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
      .width('100%')
      .padding({ left: 14, right: 16, top: 12, bottom: 12 })
      .margin({ left: 18, right: 18 })
      .backgroundColor(this.selectedNodeId.length === 0 ? Theme.SURFACE_ELEVATED : Theme.SURFACE)
      .borderRadius(16)
      .border({
        width: 1,
        color: this.selectedNodeId.length === 0 ? '#665EEAD4' : Theme.BORDER
      })
      .onClick(() => {
        this.onSelectNode('');
      })

      // Node List
      if (this.getFilteredNodes().length === 0) {
        Column({ space: 12 }) {
          Text('🌐')
            .fontSize(40)
          Text(I18n.t('暂无可用节点', 'No Nodes Available'))
            .fontSize(16)
            .fontColor(Theme.TEXT_PRIMARY)
          Text(I18n.t('点击右上角“更新”拉取账号订阅，或点击“导入”粘贴订阅链接/节点', 'Tap Sync to fetch subscription or Import to paste URL/URIs'))
            .fontSize(13)
            .fontColor(Theme.TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .padding({ left: 32, right: 32 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 10 }) {
          ForEach(this.getFilteredNodes(), (node: ProxyNode) => {
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
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.TEXT_PRIMARY)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row({ space: 6 }) {
                    Text(node.type.toUpperCase())
                      .fontSize(10)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Theme.ACCENT_BLUE)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor('#162133')
                      .borderRadius(5)
                    Text(`${node.server}:${node.port}`)
                      .fontSize(11)
                      .fontColor(Theme.TEXT_MUTED)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                  }
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
              })
            }
          }, (node: ProxyNode) => `${node.id}_${node.latencyMs}`)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 18, right: 18, bottom: 16 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }
}
