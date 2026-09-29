/**
 * SubjectsPage.ets — 科目管理（HITA_X subject/课表详情科目语义 → ArkUI）。
 *
 * P1 本地功能：展示某课表科目（学分/类型/事件数/色点）；点色块轮换配色并落库；
 * 长按删除科目（级联删除其课程事件）。数据源为演示课表（先首页生成）。
 */
import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasEventItem, EasSubjectType, EasTermSubject, EasTimetable } from '../common/model/timetable/TimetableModels';
import { TimetableLocalDemo } from '../feature/timetable/data/TimetableLocalDemo';

const PALETTE: number[] = [0xFF5C6BC0, 0xFF26A69A, 0xFFEF8E5A, 0xFFD93025, 0xFF7E57C2,
  0xFF42A5F5, 0xFF9CCC65, 0xFF8D6E63];

class SubjectRow {
  subject: EasTermSubject = new EasTermSubject();
  classCount: number = 0;
}

@Entry
@Component
struct SubjectsPage {
  @State rows: SubjectRow[] = [];
  @State summary: string = '加载中…';
  @State ready: boolean = false;

  async onPageShow(): Promise<void> {
    await this.load();
  }

  async load(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);
    const tt: EasTimetable | undefined = await rdb.getTimetableByEasCode(TimetableLocalDemo.DEMO_CODE);
    if (tt === undefined) {
      this.ready = false;
      this.rows = [];
      this.summary = '暂无演示课表：请先在首页「生成本地演示数据」。';
      return;
    }
    const subjects: EasTermSubject[] = await rdb.getSubjectsOfTimetable(tt.id);
    const out: SubjectRow[] = [];
    let creditSum: number = 0;
    let classSum: number = 0;
    for (let i = 0; i < subjects.length; i++) {
      const events: EasEventItem[] = await rdb.getClassesOfSubject(subjects[i].id);
      const row: SubjectRow = new SubjectRow();
      row.subject = subjects[i];
      row.classCount = events.length;
      creditSum += subjects[i].credit;
      classSum += events.length;
      out.push(row);
    }
    this.rows = out;
    this.summary = tt.name + ' · ' + out.length.toString() + ' 个科目 · 学分合计 ' +
      SubjectsPage.num(creditSum) + ' · 课程实例 ' + classSum.toString() + ' 次';
    this.ready = true;
  }

  async cycleColor(row: SubjectRow): Promise<void> {
    const cur: number = row.subject.color;
    let next: number = PALETTE[0];
    for (let i = 0; i < PALETTE.length; i++) {
      if (PALETTE[i] === cur) {
        next = PALETTE[(i + 1) % PALETTE.length];
        break;
      }
    }
    await RdbHelper.getInstance().changeSubjectColor(row.subject.id, next);
    row.subject.color = next;
    const copy: SubjectRow[] = [];
    for (let i = 0; i < this.rows.length; i++) {
      copy.push(this.rows[i]);
    }
    this.rows = copy; // 触发刷新
  }

  async showEvents(row: SubjectRow): Promise<void> {
    const events: EasEventItem[] = await RdbHelper.getInstance().getClassesOfSubject(row.subject.id);
    if (events.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '该科目暂无课程事件' });
      return;
    }
    const lines: string[] = [];
    for (let i = 0; i < Math.min(events.length, 30); i++) {
      const d: Date = new Date(events[i].from);
      const pad = (n: number): string => (n < 10 ? '0' + n.toString() : n.toString());
      lines.push(pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' +
        pad(d.getHours()) + ':' + pad(d.getMinutes()) + '  ' + events[i].place);
    }
    if (events.length > 30) {
      lines.push('…等 ' + events.length.toString() + ' 次');
    }
    this.getUIContext().getPromptAction().showDialog({
      title: row.subject.name + ' · ' + row.classCount.toString() + ' 次',
      message: lines.join('\n')
    }).catch(() => {
    });
  }

  async deleteSubject(row: SubjectRow): Promise<void> {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除科目',
      message: '删除「' + row.subject.name + '」及其 ' + row.classCount.toString() + ' 个课程事件？',
      buttons: [
        { text: '取消', color: '#999999' },
        { text: '删除', color: '#D93025' }
      ]
    }).then(async (ret) => {
      if (ret.index === 1) {
        const rdb: RdbHelper = RdbHelper.getInstance();
        await rdb.deleteEventsOfSubject(row.subject.id);
        await rdb.deleteSubject(row.subject.id);
        await this.load();
      }
    }).catch(() => {
    });
  }

  private static typeName(t: EasSubjectType): string {
    if (t === EasSubjectType.COM_A) {
      return '必修·考试';
    }
    if (t === EasSubjectType.COM_B) {
      return '必修·考察';
    }
    if (t === EasSubjectType.OPT_A) {
      return '选修·专选';
    }
    if (t === EasSubjectType.OPT_B) {
      return '选修·任选';
    }
    if (t === EasSubjectType.MOOC) {
      return '慕课';
    }
    return '标签';
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

        Text('科目管理')
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

      Text(this.summary)
        .fontSize(12)
        .fontColor('#666666')
        .width('100%')
        .padding({ left: 16, bottom: 6 })

      if (!this.ready) {
        Column() {
          Text(this.summary)
            .fontSize(14)
            .fontColor('#888888')
            .margin({ bottom: 12 })
          Button('生成本地演示数据')
            .fontSize(14)
            .backgroundColor('#2E7D32')
            .onClick(() => {
              const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
              TimetableLocalDemo.runSelfCheck(ctx).then(() => {
                this.load();
              });
            })
        }
        .width('100%')
        .margin({ top: 60 })
      } else if (this.rows.length === 0) {
        Text('暂无科目')
          .fontSize(14)
          .fontColor('#888888')
          .margin({ top: 60 })
      } else {
        List({ space: 8 }) {
          ForEach(this.rows, (row: SubjectRow) => {
            ListItem() {
              Row() {
                // 色块：点击轮换配色
                Row()
                  .width(22)
                  .height(22)
                  .borderRadius(11)
                  .backgroundColor(SubjectsPage.css(row.subject.color))
                  .onClick(() => {
                    this.cycleColor(row);
                  })

                Column() {
                  Text(row.subject.name)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(SubjectsPage.typeName(row.subject.type) +
                    ' · 学分 ' + SubjectsPage.num(row.subject.credit) +
                    ' · 课程 ' + row.classCount.toString() + ' 次' +
                    (row.subject.school.length > 0 ? ' · ' + row.subject.school : ''))
                    .fontSize(12)
                    .fontColor('#8A8F99')
                    .margin({ top: 3 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: 10 })

                Button('删除')
                  .fontSize(12)
                  .height(28)
                  .backgroundColor('#FFFFFF')
                  .fontColor('#D93025')
                  .border({ width: 1, color: '#D93025' })
                  .onClick(() => {
                    this.deleteSubject(row);
                  })
              }
              .width('100%')
              .padding(12)
              .backgroundColor('#FFFFFF')
              .borderRadius(10)
              .shadow({ radius: 6, color: '#12000000', offsetY: 1 })
              .onClick(() => {
                this.showEvents(row);
              })
            }
          }, (row: SubjectRow) => row.subject.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F6F8')
  }

  static num(v: number): string {
    const s: string = v.toString();
    return s.indexOf('.') < 0 ? s + '.0' : s;
  }

  static css(argb: number): string {
    const r: number = (argb >> 16) & 0xFF;
    const g: number = (argb >> 8) & 0xFF;
    const b: number = argb & 0xFF;
    return 'rgb(' + r.toString() + ',' + g.toString() + ',' + b.toString() + ')';
  }
}
