/**
 * TimetablePreview.ets — 课表周视图（真实 RDB 课表优先，演示数据兜底）。
 *
 * 状态由本页持有：展示周/事件切片/尺寸/定时刷新；Canvas 直接在页面绘制
 * （绘制函数见 feature/timetable/views/TimetableWeekDraw.ets）。
 * 手势翻周（ViewPager 环形窗口）后续接入。
 */
import { promptAction } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasEventItem, EasEventType, EasTermSubject, EasTimetable } from '../common/model/timetable/TimetableModels';
import { TimetableLocalDemo } from '../feature/timetable/data/TimetableLocalDemo';
import { TimetableResolver } from '../feature/timetable/data/TimetableResolver';
import { drawTimetableWeek, eventsOfWeek } from '../feature/timetable/views/TimetableWeekDraw';
import { IcsExporter } from '../common/util/ICSExport';

class DemoData {
  timetable: EasTimetable = new EasTimetable();
  events: EasEventItem[] = [];
}

@Entry
@Component
struct TimetablePreview {
  private demo: DemoData = new DemoData();
  @State week: number = 1;
  @State label: string = '';

  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private areaW: number = 0;
  private areaH: number = 0;
  private timer: number = -1;

  async aboutToAppear(): Promise<void> {
    // 默认用内存演示数据；已导入的真实课表优先，演示数据作为兜底。
    const memory = TimetableLocalDemo.build();
    this.demo.timetable = memory.timetable;
    this.demo.events = memory.events;
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const rdb: RdbHelper = RdbHelper.getInstance();
      await rdb.init(ctx);
      const existed: EasTimetable | undefined = await TimetableResolver.getForDisplay(rdb);
      if (existed !== undefined) {
        const subjects: EasTermSubject[] = await rdb.getSubjectsOfTimetable(existed.id);
        const colorById: Map<string, number> = new Map<string, number>();
        for (let i = 0; i < subjects.length; i++) {
          colorById.set(subjects[i].id, subjects[i].color);
        }
        let dbEvents: EasEventItem[] = await rdb.getEventsOfTimetable(existed.id);
        if (dbEvents.length > 0) {
          for (let i = 0; i < dbEvents.length; i++) {
            const ev: EasEventItem = dbEvents[i];
            const c: number | undefined = colorById.get(ev.subjectId);
            ev.color = c !== undefined ? c : TimetablePreview.defaultColor(ev.type);
          }
          this.demo.timetable = existed;
          this.demo.events = dbEvents;
        }
      }
    } catch (e) {
      // DB 不可用时保持内存演示数据
    }
    const current: number = this.demo.timetable.getWeekNumber(Date.now());
    this.week = current > 0 ? current : 1;
    this.refreshLabel();
    this.timer = setInterval(() => {
      this.drawNow();
    }, 60000);
    setTimeout(() => {
      this.drawNow();
    }, 60);
  }

  static defaultColor(t: EasEventType): number {
    if (t === EasEventType.EXAM) {
      return 0xFFD93025;
    }
    if (t === EasEventType.OTHER) {
      return 0xFF5C6BC0;
    }
    if (t === EasEventType.TAG) {
      return 0xFF26A69A;
    }
    return 0xFF2E86E8;
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private refreshLabel(): void {
    const weekEvents: EasEventItem[] = eventsOfWeek(this.demo.timetable, this.demo.events, this.week);
    this.label = '第 ' + this.week.toString() + ' 周 · 本周 ' + weekEvents.length.toString() +
      ' 项 / 共 ' + this.demo.events.length.toString() + ' 个课程实例';
  }

  private shiftWeek(delta: number): void {
    const next: number = this.week + delta;
    const max: number = this.demo.timetable.getWeekNumber(this.demo.timetable.endTime - 1);
    if (next < 1 || (max > 0 && next > max)) {
      return;
    }
    this.week = next;
    this.refreshLabel();
    this.drawNow();
  }

  private gotoToday(): void {
    const current: number = this.demo.timetable.getWeekNumber(Date.now());
    if (current > 0) {
      this.week = current;
      this.refreshLabel();
      this.drawNow();
    }
  }

  /** 导出当前课表全部事件为 .ics（手写 RFC5545，落沙箱）。 */
  async exportIcs(): Promise<void> {
    if (this.demo.events.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '无可导出事件' });
      return;
    }
    const ics: string = IcsExporter.fromEvents(this.demo.events, this.demo.timetable.name);
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const path: string = ctx.filesDir + '/hita-timetable.ics';
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, ics);
    } finally {
      fileIo.closeSync(file);
    }
    this.getUIContext().getPromptAction().showToast({ message: '已导出 ' + ics.length.toString() + 'B' });
    this.label = this.label + '\nICS: ' + path;
  }

  private drawNow(): void {
    if (this.areaW <= 0 || this.areaH <= 0) {
      return;
    }
    const weekEvents: EasEventItem[] = eventsOfWeek(this.demo.timetable, this.demo.events, this.week);
    const current: number = this.demo.timetable.getWeekNumber(Date.now());
    drawTimetableWeek(this.ctx, this.areaW, this.areaH, this.demo.timetable, weekEvents, this.week,
      current === this.week);
  }

  private onArea(w: number, h: number): void {
    this.areaW = w;
    this.areaH = h;
    this.drawNow();
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(30)
          .fontColor('#14213D')
          .width(44)
          .height(44)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })

        Column() {
          Text('第' + this.week.toString() + '周')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#14213D')
          Text(this.demo.timetable.name)
            .fontSize(17)
            .fontColor('#6B7A90')
            .margin({ top: 3 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 4 })

        Text('⇩')
          .fontSize(22)
          .fontColor('#2E86E8')
          .width(42)
          .height(42)
          .textAlign(TextAlign.Center)
          .borderRadius(21)
          .backgroundColor('#E3EEFC')
          .onClick(() => {
            this.exportIcs();
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor('#FFFFFF')
      .border({ width: { bottom: 1 }, color: '#D3DBE7' })
      .alignItems(VerticalAlign.Center)

      Column() {
        Canvas(this.ctx)
          .width('100%')
          .height('100%')
          .onReady(() => {
            this.drawNow();
          })
          .onAreaChange((oldValue: Area, newValue: Area) => {
            this.onArea(newValue.width as number, newValue.height as number);
          })
          .gesture(
            PanGesture({ direction: PanDirection.Horizontal, distance: 10 })
              .onActionEnd((event: GestureEvent) => {
                if (event.offsetX < -48) {
                  this.shiftWeek(1);   // 左滑 → 下周
                } else if (event.offsetX > 48) {
                  this.shiftWeek(-1);  // 右滑 → 上周
                }
              })
          )
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor('#F4F7FC')

    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F4F7FC')
  }
}
