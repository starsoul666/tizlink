import { promptAction } from '@kit.ArkUI';
import {
  ApiLineItem,
  AppSettings,
  DEFAULT_WHMCS_API_URL,
  RelayRegion
} from '../model/Models';
import { I18n } from '../model/I18n';
import { ApiService } from '../service/ApiService';
import { StorageService } from '../service/StorageService';
import { Theme } from './Theme';

@Component
export struct LineSelectorSheet {
  @Link settings: AppSettings;
  onClose: () => void = () => {};
  onSaved: (regionChanged: boolean, apiChanged: boolean) => void = () => {};

  @State draftRegion: RelayRegion = 'cn';
  @State draftApiUrl: string = DEFAULT_WHMCS_API_URL;
  @State draftLines: ApiLineItem[] = [];
  @State testing: boolean = false;
  @State detectingRegion: boolean = false;
  @State showAddLine: boolean = false;
  @State newLineName: string = '';
  @State newLineUrl: string = '';

  aboutToAppear(): void {
    this.draftRegion = this.settings.relayRegion;
    this.draftApiUrl = this.settings.whmcsApiUrl || DEFAULT_WHMCS_API_URL;
    this.draftLines = this.settings.apiLines.map((item: ApiLineItem) => {
      return {
        id: item.id,
        name: item.name,
        url: item.url,
        latencyMs: item.latencyMs,
        isDefault: item.isDefault
      } as ApiLineItem;
    });
  }

  private showToast(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 2200 });
    } catch (_e) {
      // ignore
    }
  }

  private async handleTestAllLines(): Promise<void> {
    if (this.testing) {
      return;
    }
    this.testing = true;
    const api: ApiService = ApiService.getInstance();
    const updated: ApiLineItem[] = this.draftLines.slice();
    for (let i: number = 0; i < updated.length; i++) {
      const line: ApiLineItem = updated[i];
      const ms: number = await api.testApiLineLatency(line.url);
      updated[i] = {
        id: line.id,
        name: line.name,
        url: line.url,
        latencyMs: ms,
        isDefault: line.isDefault
      };
      this.draftLines = updated.slice();
    }
    this.testing = false;
    this.showToast(I18n.t('线路检测完成', 'Line check completed'));
  }

  private async handleAutoDetectRegion(): Promise<void> {
    if (this.detectingRegion) {
      return;
    }
    this.detectingRegion = true;
    const detected: 'cn' | 'global' = await ApiService.getInstance().detectUserRegion();
    this.detectingRegion = false;
    this.draftRegion = detected;
    this.showToast(
      detected === 'cn'
        ? I18n.t('已自动识别为：国内线路', 'Auto-detected: Domestic (CN)')
        : I18n.t('已自动识别为：国际线路', 'Auto-detected: Global')
    );
  }

  private handleAddCustomLine(): void {
    const url: string = this.newLineUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      this.showToast(I18n.t('请输入以 https:// 或 http:// 开头的线路地址', 'URL must start with https:// or http://'));
      return;
    }
    const name: string = this.newLineName.trim() || I18n.t(`备用线路 ${this.draftLines.length}`, `Backup Line ${this.draftLines.length}`);
    const item: ApiLineItem = {
      id: `custom_${Date.now()}`,
      name: name,
      url: url,
      latencyMs: -1,
      isDefault: false
    };
    this.draftLines = [...this.draftLines, item];
    this.draftApiUrl = url;
    this.newLineName = '';
    this.newLineUrl = '';
    this.showAddLine = false;
  }

  private handleRemoveLine(id: string): void {
    const next: ApiLineItem[] = this.draftLines.filter((l: ApiLineItem) => l.id !== id);
    if (next.length === 0) {
      return;
    }
    this.draftLines = next;
    const stillExists: boolean = next.some((l: ApiLineItem) => l.url === this.draftApiUrl);
    if (!stillExists) {
      this.draftApiUrl = next[0].url;
    }
  }

  private async handleSave(): Promise<void> {
    const regionChanged: boolean = this.settings.relayRegion !== this.draftRegion;
    const apiChanged: boolean = this.settings.whmcsApiUrl !== this.draftApiUrl;
    const nextSettings: AppSettings = {
      whmcsApiUrl: this.draftApiUrl,
      apiLines: this.draftLines.slice(),
      routingMode: this.settings.routingMode,
      relayRegion: this.draftRegion,
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
    this.settings = nextSettings;
    await StorageService.getInstance().saveSettings(nextSettings);
    this.showToast(I18n.t('线路选择已保存', 'Line selection saved'));
    this.onSaved(regionChanged, apiChanged);
    this.onClose();
  }

  private formatHostPreview(url: string): string {
    return url.replace(/^https?:\/\//, '').split('/')[0];
  }

  private getLatencyLabel(ms: number): string {
    if (ms === -1) {
      return I18n.t('未测速', 'Untested');
    }
    if (ms === -2) {
      return I18n.t('不可用', 'Unavailable');
    }
    return `${ms} ms`;
  }

  private getLatencyColor(ms: number): string {
    if (ms === -1) {
      return Theme.TEXT_MUTED;
    }
    if (ms === -2) {
      return Theme.ACCENT_RED;
    }
    if (ms < 300) {
      return Theme.ACCENT_GREEN;
    }
    if (ms < 800) {
      return Theme.ACCENT_AMBER;
    }
    return Theme.ACCENT_RED;
  }

  build() {
    Column() {
      Column({ space: 14 }) {
        // Sheet Header
        Row() {
          Text(I18n.t('线路选择', 'Line Selection'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT_PRIMARY)
          Blank()
          Button(this.testing ? I18n.t('检测中...', 'Testing...') : I18n.t('检测线路', 'Test Lines'))
            .height(32)
            .fontSize(12)
            .fontColor(Theme.ACCENT_MINT)
            .backgroundColor('#162B2E')
            .borderRadius(9)
            .margin({ right: 10 })
            .enabled(!this.testing)
            .onClick(() => {
              void this.handleTestAllLines();
            })
          Text('✕')
            .fontSize(18)
            .fontColor(Theme.TEXT_SECONDARY)
            .width(30)
            .height(30)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')

        Scroll() {
          Column({ space: 14 }) {
            // Section 1: Domestic / Global Region Line Selection
            Row() {
              Text(I18n.t('接入区域线路', 'Region Line'))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TEXT_SECONDARY)
              Blank()
              Text(this.detectingRegion ? I18n.t('识别中...', 'Detecting...') : I18n.t('自动识别地区', 'Auto Detect'))
                .fontSize(12)
                .fontColor(Theme.ACCENT_BLUE)
                .onClick(() => {
                  void this.handleAutoDetectRegion();
                })
            }
            .width('100%')

            Column({ space: 8 }) {
              this.buildRegionCard(
                'cn',
                I18n.t('国内线路', 'Domestic Line (CN)'),
                I18n.t('适用于中国大陆地区，采用国内优化中转入口', 'For Mainland China users with optimized relay')
              )
              this.buildRegionCard(
                'global',
                I18n.t('国际线路', 'Global Line'),
                I18n.t('仅适用于中国大陆以外海外地区使用', 'For users outside Mainland China')
              )
              this.buildRegionCard(
                'auto',
                I18n.t('自动匹配', 'Auto Region'),
                I18n.t('根据当前网络地区自动选择最优接入线路', 'Automatically pick best line by network location')
              )
            }
            .width('100%')

            Text(
              this.draftRegion === 'global'
                ? I18n.t('提示：国际线路仅适用于中国大陆以外地区，在中国大陆使用可能导致无法正常连接。', 'Note: Global line is for overseas use only.')
                : I18n.t('提示：国内线路仅适用于中国大陆地区，在海外使用请切换至国际线路。', 'Note: Domestic line is optimized for Mainland China.')
            )
              .fontSize(11)
              .fontColor(Theme.TEXT_MUTED)
              .lineHeight(17)
              .width('100%')

            Divider().color(Theme.BORDER)

            // Section 2: TizLink API Access Lines
            Row() {
              Text(I18n.t('API 接入线路', 'API Access Lines'))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TEXT_SECONDARY)
              Blank()
              Text(this.showAddLine ? I18n.t('收起', 'Hide') : I18n.t('+ 添加备用线路', '+ Add Backup'))
                .fontSize(12)
                .fontColor(Theme.ACCENT_MINT)
                .onClick(() => {
                  this.showAddLine = !this.showAddLine;
                })
            }
            .width('100%')

            if (this.showAddLine) {
              Column({ space: 8 }) {
                TextInput({ text: this.newLineName, placeholder: I18n.t('线路名称（如：备用线路 2）', 'Line Name') })
                  .height(40)
                  .fontSize(13)
                  .fontColor(Theme.TEXT_PRIMARY)
                  .placeholderColor(Theme.TEXT_MUTED)
                  .backgroundColor(Theme.INPUT_BG)
                  .borderRadius(10)
                  .border({ width: 1, color: Theme.BORDER })
                  .padding({ left: 10, right: 10 })
                  .onChange((v: string) => {
                    this.newLineName = v;
                  })
                TextInput({ text: this.newLineUrl, placeholder: 'https://.../v2raysocks_client.php' })
                  .height(40)
                  .fontSize(12)
                  .fontColor(Theme.TEXT_PRIMARY)
                  .placeholderColor(Theme.TEXT_MUTED)
                  .backgroundColor(Theme.INPUT_BG)
                  .borderRadius(10)
                  .border({ width: 1, color: Theme.BORDER })
                  .padding({ left: 10, right: 10 })
                  .onChange((v: string) => {
                    this.newLineUrl = v;
                  })
                Button(I18n.t('添加并选中', 'Add & Select'))
                  .width('100%')
                  .height(38)
                  .fontSize(13)
                  .borderRadius(10)
                  .backgroundColor(Theme.SURFACE_ELEVATED)
                  .fontColor(Theme.ACCENT_MINT)
                  .onClick(() => {
                    this.handleAddCustomLine();
                  })
              }
              .width('100%')
              .padding(10)
              .backgroundColor('#0F1218')
              .borderRadius(12)
              .border({ width: 1, color: Theme.BORDER })
            }

            Column({ space: 8 }) {
              ForEach(this.draftLines, (line: ApiLineItem) => {
                Row({ space: 10 }) {
                  Circle()
                    .width(8)
                    .height(8)
                    .fill(
                      line.latencyMs > 0
                        ? Theme.ACCENT_GREEN
                        : line.latencyMs === -2
                          ? Theme.ACCENT_RED
                          : Theme.TEXT_MUTED
                    )

                  Column({ space: 2 }) {
                    Text(line.name)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Theme.TEXT_PRIMARY)
                    Text(this.formatHostPreview(line.url))
                      .fontSize(11)
                      .fontColor(Theme.TEXT_MUTED)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  Text(this.getLatencyLabel(line.latencyMs))
                    .fontSize(11)
                    .fontColor(this.getLatencyColor(line.latencyMs))

                  if (!line.isDefault) {
                    Text('✕')
                      .fontSize(13)
                      .fontColor(Theme.ACCENT_RED)
                      .padding({ left: 6, right: 4 })
                      .onClick(() => {
                        this.handleRemoveLine(line.id);
                      })
                  }

                  if (this.draftApiUrl === line.url) {
                    Text('✓')
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Theme.ACCENT_MINT)
                  }
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 12, bottom: 12 })
                .backgroundColor(this.draftApiUrl === line.url ? Theme.SURFACE_ELEVATED : Theme.INPUT_BG)
                .borderRadius(12)
                .border({
                  width: 1,
                  color: this.draftApiUrl === line.url ? '#665EEAD4' : Theme.BORDER
                })
                .onClick(() => {
                  this.draftApiUrl = line.url;
                })
              }, (line: ApiLineItem) => `${line.id}_${line.latencyMs}`)
            }
            .width('100%')
          }
        }
        .constraintSize({ maxHeight: 420 })
        .scrollBar(BarState.Off)

        // Save Button
        Button(I18n.t('保存线路选择', 'Save Line Selection'))
          .width('100%')
          .height(46)
          .borderRadius(14)
          .backgroundColor(Theme.PRIMARY_BTN_BG)
          .fontColor(Theme.PRIMARY_BTN_TEXT)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .onClick(() => {
            void this.handleSave();
          })
      }
      .width('92%')
      .constraintSize({ maxWidth: 460 })
      .padding(20)
      .backgroundColor(Theme.SURFACE)
      .borderRadius(22)
      .border({ width: 1, color: Theme.BORDER_LIGHT })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#B3000000')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private buildRegionCard(region: RelayRegion, title: string, desc: string) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.draftRegion === region ? Theme.TEXT_PRIMARY : Theme.TEXT_SECONDARY)
        Text(desc)
          .fontSize(11)
          .fontColor(Theme.TEXT_MUTED)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.draftRegion === region) {
        Text('✓')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.ACCENT_MINT)
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .backgroundColor(this.draftRegion === region ? Theme.SURFACE_ELEVATED : Theme.INPUT_BG)
    .borderRadius(12)
    .border({
      width: 1,
      color: this.draftRegion === region ? '#665EEAD4' : Theme.BORDER
    })
    .onClick(() => {
      this.draftRegion = region;
    })
  }
}
