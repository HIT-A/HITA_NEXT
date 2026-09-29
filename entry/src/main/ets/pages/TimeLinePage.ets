/**
 * TimeLinePage.ets — 今日时间线（HITA_X ui/main/timeline 语义 → ArkUI List）。
 *
 * P0/P1：读本地 events 中"今天 00:00 ~ 明天 00:00"事件，按开始时间排序展示；
 * 无数据时提示一键生成演示数据（含今日/明日事件）。
 */
import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasEventItem, EasEventType } from '../common/model/timetable/TimetableModels';
import { DOW_FULL, EasTimeTools } from '../common/util/EasTimeTools';
import { TimetableLocalDemo } from '../feature/timetable/data/TimetableLocalDemo';

const DAY_MS: number = 24 * 60 * 60 * 1000;

@Entry
@Component
struct TimeLinePage {
  @State items: EasEventItem[] = [];
  @State header: string = '';
  @State emptyText: string = '本日暂无日程';
  @State loaded: boolean = false;
  @State loading: boolean = false;
  @State dayOffset: number = 0;

  private shiftDay(delta: number): void {
    let d: number = this.dayOffset + delta;
    if (d < -30) {
      d = -30;
    }
    if (d > 30) {
      d = 30;
    }
    this.dayOffset = d;
    this.reload();
  }

  async onPageShow(): Promise<void> {
    await this.reload();
  }

  onEventLongPress(ev: EasEventItem): void {
    this.getUIContext().getPromptAction().showActionMenu({
      title: ev.name,
      buttons: [
        { text: '编辑', color: '#2B6CB0' },
        { text: '删除', color: '#D93025' }
      ]
    }).then((ret) => {
      if (ret.index === 0) {
        this.getUIContext().getRouter().pushUrl({ url: 'pages/AddEventPage', params: { 'id': ev.id } });
      } else if (ret.index === 1) {
        this.confirmDelete(ev);
      }
    }).catch(() => {
    });
  }

  async confirmDelete(ev: EasEventItem): Promise<void> {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除事件',
      message: '确定删除「' + ev.name + '」？',
      buttons: [
        { text: '取消', color: '#999999' },
        { text: '删除', color: '#D93025' }
      ]
    }).then((ret) => {
      if (ret.index === 1) {
        const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
        RdbHelper.getInstance().init(ctx).then(() => {
          return RdbHelper.getInstance().deleteEvent(ev.id);
        }).then(() => {
          this.getUIContext().getPromptAction().showToast({ message: '已删除' });
          this.reload();
        });
      }
    }).catch(() => {
    });
  }

  async reload(): Promise<void> {
    this.loading = true;
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const rdb: RdbHelper = RdbHelper.getInstance();
      await rdb.init(ctx);
      const today0: number = new Date(new Date().setHours(0, 0, 0, 0)).getTime();
      const day0: number = today0 + this.dayOffset * DAY_MS;
      const dayItems: EasEventItem[] = await rdb.getEventsDuring(day0, day0 + DAY_MS);
      // 目标日（按开始时间升序）
      dayItems.sort((a: EasEventItem, b: EasEventItem): number => {
        return a.from - b.from;
      });
      this.items = dayItems;
      const now: number = Date.now();
      const tag: string = EasTimeTools.relativeDayTag(day0);
      this.header = EasTimeTools.printDate(day0) + ' ' +
        DOW_FULL[EasTimeTools.getDow(day0)] +
        (tag.length > 0 ? ' · ' + tag : '') + ' · ' + dayItems.length.toString() + ' 项';
      this.emptyText = '该日暂无日程';
      this.loaded = true;
    } catch (e) {
      this.emptyText = '读取失败：' + (e as Error).message;
      this.loaded = false;
    } finally {
      this.loading = false;
    }
  }

  async seedDemo(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    await TimetableLocalDemo.runSelfCheck(ctx);
    await this.reload();
  }

  private ongoing(ev: EasEventItem): boolean {
    const now: number = Date.now();
    return ev.from <= now && ev.to >= now;
  }

  private past(ev: EasEventItem): boolean {
    return ev.to < Date.now();
  }

  private upcomingSoon(ev: EasEventItem): boolean {
    const d: number = ev.from - Date.now();
    return !this.past(ev) && !this.ongoing(ev) && d <= 15 * 60 * 1000;
  }

  build() {
    Column() {
      // ── Header Bar ──
      Row() {
        Text('<')
          .fontSize(22)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })

        Text('时间线')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
          .margin({ left: 4 })

        Text('＋')
          .fontSize(22)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/AddEventPage',
              params: { 'offset': this.dayOffset }
            });
          })

        Text('↻')
          .fontSize(20)
          .fontColor('#FFFFFF')
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.reload();
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
      .backgroundColor('#3390EC')
      .alignItems(VerticalAlign.Center)

      // ── Sub-header info ──
      Text(this.header)
        .fontSize(13)
        .fontColor('#808080')
        .alignSelf(ItemAlign.Start)
        .padding({ left: 16, right: 16, top: 12, bottom: 4 })

      // ── Date navigation pills ──
      Row({ space: 8 }) {
        Text('‹ 前一天')
          .fontSize(13)
          .fontColor('#808080')
          .height(34)
          .padding({ left: 16, right: 16 })
          .backgroundColor('#FFFFFF')
          .borderRadius(20)
          .border({ width: 1, color: '#E0E0E0' })
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.shiftDay(-1);
          })

        Text('今天')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dayOffset === 0 ? '#FFFFFF' : '#808080')
          .height(34)
          .padding({ left: 20, right: 20 })
          .backgroundColor(this.dayOffset === 0 ? '#3390EC' : '#FFFFFF')
          .borderRadius(20)
          .border({ width: 1, color: this.dayOffset === 0 ? '#3390EC' : '#E0E0E0' })
          .textAlign(TextAlign.Center)
          .onClick(() => {
            if (this.dayOffset !== 0) {
              this.dayOffset = 0;
              this.reload();
            }
          })

        Text('后一天 ›')
          .fontSize(13)
          .fontColor('#808080')
          .height(34)
          .padding({ left: 16, right: 16 })
          .backgroundColor('#FFFFFF')
          .borderRadius(20)
          .border({ width: 1, color: '#E0E0E0' })
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.shiftDay(1);
          })

        Blank()

        Text('±30天')
          .fontSize(11)
          .fontColor('#B0B4BA')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      // ── Content area ──
      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color('#3390EC')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (!this.loaded) {
        Column() {
          Text('⚠')
            .fontSize(40)
            .margin({ bottom: 12 })
          Text(this.emptyText)
            .fontSize(14)
            .fontColor('#808080')
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 32, right: 32 })
      } else if (this.items.length === 0) {
        Column() {
          Text('◷')
            .fontSize(48)
            .margin({ bottom: 12 })
          Text(this.emptyText)
            .fontSize(15)
            .fontColor('#808080')
            .textAlign(TextAlign.Center)
            .margin({ bottom: 20 })
          if (this.dayOffset === 0) {
            Text('生成演示数据')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .height(40)
              .padding({ left: 24, right: 24 })
              .backgroundColor('#3390EC')
              .borderRadius(20)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.seedDemo();
              })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 10 }) {
          ForEach(this.items, (ev: EasEventItem) => {
            ListItem() {
              Row() {
                // ── Left color bar ──
                Column()
                  .width(4)
                  .height('100%')
                  .borderRadius(2)
                  .backgroundColor(TimeLinePage.typeColor(ev.type))

                // ── Time column ──
                Column() {
                  Text(EasTimeTools.printTime(ev.from))
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.past(ev) ? '#B0B4BA' : '#1A1A1A')
                  Text(EasTimeTools.printTime(ev.to))
                    .fontSize(11)
                    .fontColor('#B0B4BA')
                    .margin({ top: 2 })
                }
                .width(56)
                .alignItems(HorizontalAlign.Center)
                .justifyContent(FlexAlign.Center)
                .margin({ left: 10 })

                // ── Content column ──
                Column() {
                  Row({ space: 6 }) {
                    // Type badge
                    Text(TimeLinePage.typeName(ev.type))
                      .fontSize(10)
                      .fontColor('#FFFFFF')
                      .fontWeight(FontWeight.Medium)
                      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                      .borderRadius(10)
                      .backgroundColor(TimeLinePage.typeColor(ev.type))

                    // Status indicator
                    if (this.ongoing(ev)) {
                      Row({ space: 4 }) {
                        Circle({ width: 6, height: 6 })
                          .fill('#D93025')
                        Text('进行中')
                          .fontSize(10)
                          .fontColor('#D93025')
                          .fontWeight(FontWeight.Medium)
                      }
                      .alignItems(VerticalAlign.Center)
                    } else if (this.upcomingSoon(ev)) {
                      Row({ space: 4 }) {
                        Circle({ width: 6, height: 6 })
                          .fill('#3390EC')
                        Text('即将开始')
                          .fontSize(10)
                          .fontColor('#3390EC')
                          .fontWeight(FontWeight.Medium)
                      }
                      .alignItems(VerticalAlign.Center)
                    } else if (this.past(ev)) {
                      Row({ space: 4 }) {
                        Circle({ width: 6, height: 6 })
                          .fill('#B0B4BA')
                        Text('已结束')
                          .fontSize(10)
                          .fontColor('#B0B4BA')
                      }
                      .alignItems(VerticalAlign.Center)
                    }
                  }
                  .width('100%')

                  Text(ev.name)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.past(ev) ? '#B0B4BA' : '#1A1A1A')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                    .margin({ top: 4 })

                  if (ev.place.length > 0 || ev.teacher.length > 0) {
                    Text((ev.place.length > 0 ? ev.place : '') +
                      (ev.place.length > 0 && ev.teacher.length > 0 ? ' · ' : '') +
                      (ev.teacher.length > 0 ? ev.teacher : ''))
                      .fontSize(12)
                      .fontColor('#808080')
                      .width('100%')
                      .margin({ top: 2 })
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: 10 })
              }
              .width('100%')
              .padding({ top: 12, bottom: 12, left: 0, right: 14 })
              .backgroundColor('#FFFFFF')
              .borderRadius(12)
              .shadow({ radius: 8, color: '#14000000', offsetY: 2 })
              .alignItems(VerticalAlign.Top)
              .gesture(
                LongPressGesture({ repeat: false })
                  .onAction(() => {
                    this.onEventLongPress(ev);
                  })
              )
            }
          }, (ev: EasEventItem) => ev.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 14, right: 14, top: 4 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F7FA')
  }

  static typeName(t: EasEventType): string {
    if (t === EasEventType.EXAM) {
      return '考试';
    }
    if (t === EasEventType.OTHER) {
      return '日程';
    }
    if (t === EasEventType.TAG) {
      return '备忘';
    }
    return '课程';
  }

  static typeColor(t: EasEventType): string {
    if (t === EasEventType.EXAM) {
      return '#D93025';
    }
    if (t === EasEventType.OTHER) {
      return '#5C6BC0';
    }
    if (t === EasEventType.TAG) {
      return '#26A69A';
    }
    return '#3390EC';
  }
}
