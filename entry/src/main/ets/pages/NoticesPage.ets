/**
 * NoticesPage.ets — 公告列表（Android AppNoticesActivity 同源）。
 *
 * 先渲染缓存，再拉取最新并刷新；仅展示生效中的公告（时间窗 + 版本范围），
 * critical 排前。空态“暂无公告”。
 */
import { common } from '@kit.AbilityKit';
import { AppNotice, AppNoticeCenter } from '../feature/notice/AppNoticeCenter';

@Entry
@Component
struct NoticesPage {
  @State notices: AppNotice[] = [];
  @State loading: boolean = true;

  async aboutToAppear(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    this.notices = AppNoticeCenter.activeNotices(await AppNoticeCenter.cachedNotices(ctx));
    this.loading = false;
    const fetched: AppNotice[] = await AppNoticeCenter.fetch(ctx);
    this.notices = AppNoticeCenter.activeNotices(fetched);
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(30)
          .fontColor('#1A1A1A')
          .fontWeight(FontWeight.Bold)
          .width(44)
          .height(44)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })

        Text('公告')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
          .layoutWeight(1)
          .margin({ left: 4 })
      }
      .width('100%')
      .padding({ left: 8, right: 16, top: 8, bottom: 8 })
      .backgroundColor('#FFFFFF')
      .border({ width: { bottom: 1 }, color: '#EAECF0' })
      .alignItems(VerticalAlign.Center)

      if (this.loading) {
        LoadingProgress()
          .width(32)
          .height(32)
          .color('#3390EC')
          .margin({ top: 80 })
      } else if (this.notices.length === 0) {
        Text('暂无公告')
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
          }, (notice: AppNotice) => notice.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 12 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F7FA')
  }
}
