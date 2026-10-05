/**
 * NoticesPage.ets — 公告列表（Android AppNoticesActivity 同源）。
 *
 * 先渲染缓存，再拉取最新并刷新；仅展示生效中的公告（时间窗 + 版本范围），
 * critical 排前。空态“暂无公告”。
 */
import { common } from '@kit.AbilityKit';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { AppNotice, AppNoticeCenter } from '../feature/notice/AppNoticeCenter';

@Entry
@Component
struct NoticesPage {
  @State notices: AppNotice[] = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorMessage: string = '';

  async aboutToAppear(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    try {
      this.notices = AppNoticeCenter.activeNotices(await AppNoticeCenter.cachedNotices(ctx));
    } catch (e) {
      this.notices = [];
    }
    // 有缓存时立即显示；没有缓存时保留加载态，避免把网络等待误报成空公告。
    this.loading = this.notices.length === 0;
    await this.refreshNotices();
  }

  private async refreshNotices(): Promise<void> {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    this.errorMessage = '';
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    try {
      const fetched: AppNotice[] = await AppNoticeCenter.fetch(ctx);
      this.notices = AppNoticeCenter.activeNotices(fetched);
    } catch (e) {
      this.errorMessage = this.notices.length > 0 ?
        '公告更新失败，当前显示上次保存的内容' : '公告暂时无法加载';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  build() {
    Column() {
      Row() {
        HeaderBackButton({
          onBack: () => this.getUIContext().getRouter().back()
        })
          .margin({ right: 12 })
        Text('公告')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Button({ type: ButtonType.Circle }) {
          if (this.refreshing) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color('#3390EC')
          } else {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(20)
              .fontColor(['#566276'])
          }
        }
        .width(44)
        .height(44)
        .padding(0)
        .backgroundColor('#F2F4F7')
        .enabled(!this.refreshing)
        .accessibilityText('刷新公告')
        .onClick(() => {
          this.refreshNotices();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor('#FFFFFF')
      .border({ width: { bottom: 1 }, color: '#EAECF0' })
      .alignItems(VerticalAlign.Center)

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(13)
          .fontColor('#8C3A3A')
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .backgroundColor('#FDECEC')
      }

      if (this.loading) {
        LoadingProgress()
          .width(32)
          .height(32)
          .color('#3390EC')
          .margin({ top: 80 })
      } else if (this.notices.length === 0) {
        Text(this.errorMessage.length > 0 ? '暂未获取到公告' : '暂无公告')
          .fontSize(14)
          .fontColor('#888888')
          .margin({ top: 60 })
      } else {
        List({ space: 12 }) {
          ForEach(this.notices, (notice: AppNotice) => {
            ListItem() {
              Column() {
                Row() {
                  Text(notice.title)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#1A1A1A')
                    .layoutWeight(1)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (notice.isCritical()) {
                    Text('重要')
                      .fontSize(11)
                      .fontColor('#D93025')
                      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                      .backgroundColor('#FFFFFF')
                      .borderRadius(10)
                  }
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                Text(notice.body)
                  .fontSize(13)
                  .lineHeight(20)
                  .fontColor(notice.isCritical() ? '#8C3A3A' : '#566276')
                  .width('100%')
                  .margin({ top: 8 })
              }
              .width('100%')
              .padding(16)
              .backgroundColor(notice.isCritical() ? '#FDECEC' : '#FFFFFF')
              .borderRadius(16)
            }
          }, (notice: AppNotice) => notice.renderKey())
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F7FA')
  }
}
