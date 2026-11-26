import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { Theme } from '../components/Theme';

interface WebPageParams {
  title?: string;
  url?: string;
}

@Entry
@Component
struct WebSupportPage {
  private controller: webview.WebviewController = new webview.WebviewController();
  @State title: string = 'TizLink';
  @State targetUrl: string = '';
  @State progress: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as WebPageParams | undefined;
    if (params) {
      if (params.title) {
        this.title = params.title;
      }
      if (params.url) {
        this.targetUrl = params.url;
      }
    }
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Text('‹')
          .fontSize(26)
          .fontColor(Theme.TEXT_PRIMARY)
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            router.back();
          })
        Text(this.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('↻')
          .fontSize(18)
          .fontColor(Theme.TEXT_SECONDARY)
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            try {
              this.controller.refresh();
            } catch (_e) {
              // ignore
            }
          })
      }
      .width('100%')
      .height(54)
      .padding({ left: 10, right: 10 })
      .backgroundColor(Theme.NAV_BG)
      .border({ width: { bottom: 1 }, color: Theme.BORDER })

      if (this.progress > 0 && this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color(Theme.ACCENT_MINT)
          .backgroundColor(Theme.BG)
      }

      if (this.targetUrl.length > 0) {
        Web({ src: this.targetUrl, controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .layoutWeight(1)
          .width('100%')
          .onProgressChange((event) => {
            if (event) {
              this.progress = event.newProgress;
            }
          })
      } else {
        Column() {
          Text('无效的页面地址')
            .fontSize(14)
            .fontColor(Theme.TEXT_SECONDARY)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
