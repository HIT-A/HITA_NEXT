/**
 * WebBrowserPage.ets — 应用内浏览器：打开资讯文章与校园入口链接。
 */
import { webview } from '@kit.ArkWeb';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';

@Entry
@Component
struct WebBrowserPage {
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  @State url: string = '';
  @State titleText: string = '详情';
  @State progress: number = 0;
  @State failed: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    const params: Object | undefined = this.getUIContext().getRouter().getParams();
    if (params !== undefined && params !== null) {
      const record: Record<string, string> = params as Record<string, string>;
      this.url = record['url'] === undefined ? '' : String(record['url']);
      if (record['title'] !== undefined && String(record['title']).length > 0) {
        this.titleText = String(record['title']);
      }
    }
  }

  private goBack(): void {
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
        return;
      }
    } catch (e) {
      // The web view may not be attached yet; fall back to leaving the page.
    }
    this.getUIContext().getRouter().back();
  }

  onBackPress(): boolean {
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
        return true;
      }
    } catch (e) {
    }
    return false;
  }

  build() {
    Column() {
      Row() {
        HeaderBackButton({
          onBack: () => this.goBack()
        })
          .margin({ right: 12 })
        Text(this.titleText)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(18)
            .fontColor(['#2E86E8'])
        }
        .width(40)
        .height(40)
        .backgroundColor('#F2F4F7')
        .accessibilityText('刷新')
        .onClick(() => {
          this.failed = false;
          try {
            this.controller.refresh();
          } catch (e) {
          }
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor('#FFFFFF')
      .alignItems(VerticalAlign.Center)

      if (this.progress > 0 && this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color('#2E86E8')
      }

      if (this.url.length === 0) {
        Text('没有可打开的链接')
          .fontSize(14)
          .fontColor('#5A6880')
          .margin({ top: 60 })
      } else {
        Stack() {
          Web({ src: this.url, controller: this.controller })
            .width('100%')
            .height('100%')
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .onlineImageAccess(true)
            .mixedMode(MixedMode.All)
            .onProgressChange((event) => {
              if (event !== undefined) {
                this.progress = event.newProgress;
              }
            })
            .onErrorReceive((event) => {
              if (event !== undefined && event.request.isMainFrame()) {
                this.failed = true;
              }
            })
          if (this.failed) {
            Column() {
              Text('页面加载失败，请检查网络后点右上角刷新')
                .fontSize(14)
                .fontColor('#4E5C72')
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#F6F7FA')
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarInset })
    .backgroundColor('#FFFFFF')
  }
}
