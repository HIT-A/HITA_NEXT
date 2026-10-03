/**
 * ProfilePage.ets — 我的 / 会话管理（HITA_X ui/myprofile + user 本地模型 语义 → feature/profile）。
 *
 * 蓝本：个人资料本地化（EAS 登录身份回填展示），不含云端账号。
 * 功能：查看当前登录会话身份/会话代数/webBaseUrl；单校区退出；一键清除全部本地数据(演示重置)。
 */
import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { EasCampus, EasSession } from '../feature/eas/EasSession';
import { EasSessionStore } from '../feature/eas/EasSessionStore';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasEventItem, EasEventType, EasSubjectType, EasTermSubject, EasTimetable } from '../common/model/timetable/TimetableModels';

@Entry
@Component
struct ProfilePage {
  @State summary: string = '';
  @State selectedCampus: string = 'SHENZHEN';
  @State hasSession: boolean = false;
  @State userName: string = '';
  @State userCampusLabel: string = '';
  @State userStuId: string = '';
  @State sessionGen: number = 0;
  @State detailRows: Array<string[]> = [];

  async onPageShow(): Promise<void> {
    await this.refresh();
  }

  async refresh(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    await EasSessionStore.getInstance().init(ctx);
    const campus: EasCampus = ProfilePage.campusOf(this.selectedCampus);
    const s: EasSession | undefined = await EasSessionStore.getInstance().load(campus);
    if (s === undefined || !s.isLogin()) {
      this.hasSession = false;
      this.summary = '（' + campus.toString() + ' 无会话）';
      this.userName = '';
      this.userCampusLabel = ProfilePage.campusLabel(campus);
      this.userStuId = '';
      this.sessionGen = 0;
      this.detailRows = [];
      return;
    }
    this.hasSession = true;
    this.userName = s.name.length > 0 ? s.name : s.username;
    this.userCampusLabel = ProfilePage.campusLabel(campus);
    this.userStuId = s.stuId;
    this.sessionGen = s.sessionGeneration;
    const rows: string[] = [];
    rows.push('校区：' + campus.toString() + '（' + ProfilePage.campusLabel(campus) + '）');
    if (s.name.length > 0) {
      rows.push('姓名：' + s.name);
    }
    if (s.stuId.length > 0) {
      rows.push('学号：' + s.stuId);
    }
    if (s.school.length > 0) {
      rows.push('院系：' + s.school);
    }
    if (s.major.length > 0) {
      rows.push('专业：' + s.major);
    }
    if (s.grade.length > 0) {
      rows.push('年级：' + s.grade);
    }
    if (s.username.length > 0) {
      rows.push('账号：' + s.username);
    }
    rows.push('会话代数：' + s.sessionGeneration.toString());
    rows.push('门户 Cookie：' + s.webCookies.size.toString() + ' 项');
    if (s.webBaseUrl.length > 0) {
      rows.push('数据基址：' + s.webBaseUrl);
    }
    if (s.electronicExpToken.length > 0) {
      rows.push('电子实验 Token：已获取');
    }
    this.summary = rows.join('\n');
    // Build structured detail rows for the card
    const details: Array<string[]> = [];
    details.push(['校区', campus.toString() + '（' + ProfilePage.campusLabel(campus) + '）']);
    if (s.name.length > 0) {
      details.push(['姓名', s.name]);
    }
    if (s.stuId.length > 0) {
      details.push(['学号', s.stuId]);
    }
    if (s.school.length > 0) {
      details.push(['院系', s.school]);
    }
    if (s.major.length > 0) {
      details.push(['专业', s.major]);
    }
    if (s.grade.length > 0) {
      details.push(['年级', s.grade]);
    }
    if (s.username.length > 0) {
      details.push(['账号', s.username]);
    }
    details.push(['会话代数', s.sessionGeneration.toString()]);
    details.push(['门户 Cookie', s.webCookies.size.toString() + ' 项']);
    if (s.webBaseUrl.length > 0) {
      details.push(['数据基址', s.webBaseUrl]);
    }
    if (s.electronicExpToken.length > 0) {
      details.push(['电子实验 Token', '已获取']);
    }
    this.detailRows = details;
  }

  async logoutSelected(): Promise<void> {
    this.getUIContext().getPromptAction().showDialog({
      title: '退出登录',
      message: '清除 ' + this.selectedCampus + ' 会话 Cookie 并退出？',
      buttons: [
        { text: '取消', color: '#999999' },
        { text: '退出', color: '#D93025' }
      ]
    }).then((ret) => {
      if (ret.index === 1) {
        EasSessionStore.getInstance().clear(ProfilePage.campusOf(this.selectedCampus)).then(() => {
          this.getUIContext().getPromptAction().showToast({ message: '已退出 ' + this.selectedCampus });
          this.refresh();
        });
      }
    }).catch(() => {
    });
  }

  async clearAllLocal(): Promise<void> {
    this.getUIContext().getPromptAction().showDialog({
      title: '清除全部本地数据',
      message: '删除三个校区的会话、演示课表与本地事件？',
      buttons: [
        { text: '取消', color: '#999999' },
        { text: '清除', color: '#D93025' }
      ]
    }).then(async (ret) => {
      if (ret.index !== 1) {
        return;
      }
      const store: EasSessionStore = EasSessionStore.getInstance();
      await store.clear(EasCampus.SHENZHEN);
      await store.clear(EasCampus.BENBU);
      await store.clear(EasCampus.WEIHAI);
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const rdb: RdbHelper = RdbHelper.getInstance();
      await rdb.init(ctx);
      await rdb.clearTable('timetable');
      await rdb.clearTable('subject');
      await rdb.clearTable('events');
      this.getUIContext().getPromptAction().showToast({ message: '本地数据已清除' });
      this.refresh();
    }).catch(() => {
    });
  }

  /** 导出三表为 JSON 备份到应用沙箱（蓝本 §6：一次性导入/导出 JSON）。 */
  async exportLocalJson(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);
    const timetables = await rdb.getTimetables();
    const subjects: EasTermSubject[] = [];
    const events: EasEventItem[] = [];
    for (let i = 0; i < timetables.length; i++) {
      const tt = timetables[i];
      const ss = await rdb.getSubjectsOfTimetable(tt.id);
      for (let j = 0; j < ss.length; j++) {
        subjects.push(ss[j]);
      }
      const es = await rdb.getEventsOfTimetable(tt.id);
      for (let j = 0; j < es.length; j++) {
        events.push(es[j]);
      }
    }
    const payload: Record<string, Object> = {
      'exportedAt': Date.now(),
      'timetables': timetables.map((t) => ProfilePage.timetableOut(t)),
      'subjects': subjects.map((s) => ProfilePage.subjectOut(s)),
      'events': events.map((e) => ProfilePage.eventOut(e))
    };
    const json: string = JSON.stringify(payload);
    const path: string = ctx.filesDir + '/hita-backup.json';
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, json);
    } finally {
      fileIo.closeSync(file);
    }
    this.getUIContext().getPromptAction().showToast({ message: '已导出 ' + json.length.toString() + 'B' });
    this.summary = '导出成功：' + path + '\n课表 ' + timetables.length.toString() +
      ' / 科目 ' + subjects.length.toString() + ' / 事件 ' + events.length.toString();
    this.hasSession = true;
  }

  static timetableOut(t: EasTimetable): Record<string, Object> {
    return {
      'id': t.id, 'name': t.name, 'code': t.code, 'startTime': t.startTime, 'endTime': t.endTime,
      'scheduleStructure': EasTimetable.encodeStructure(t.scheduleStructure)
    };
  }

  static subjectOut(s: EasTermSubject): Record<string, Object> {
    return {
      'id': s.id, 'timetableId': s.timetableId, 'name': s.name, 'type': s.type.toString(),
      'field': s.field, 'credit': s.credit, 'school': s.school, 'countInSPA': s.countInSPA ? 1 : 0,
      'code': s.code, 'key': s.key, 'color': s.color
    };
  }

  static eventOut(e: EasEventItem): Record<string, Object> {
    return {
      'id': e.id, 'type': e.type.toString(), 'name': e.name, 'place': e.place, 'teacher': e.teacher,
      'subjectId': e.subjectId, 'timetableId': e.timetableId, 'from': e.from, 'to': e.to,
      'fromNumber': e.fromNumber, 'lastNumber': e.lastNumber
    };
  }

  /** 从沙箱 hita-backup.json 恢复（覆盖式导入，蓝本 §6 JSON 一次性迁移）。 */
  async importLocalJson(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const path: string = ctx.filesDir + '/hita-backup.json';
    let json: string = '';
    try {
      json = fileIo.readTextSync(path);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '未找到备份文件' });
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '从备份恢复',
      message: '将清空本地三表并用备份覆盖导入，继续？',
      buttons: [
        { text: '取消', color: '#999999' },
        { text: '恢复', color: '#00696D' }
      ]
    }).then(async (ret) => {
      if (ret.index !== 1) {
        return;
      }
      const rdb: RdbHelper = RdbHelper.getInstance();
      await rdb.init(ctx);
      let parsed: Record<string, Object>;
      try {
        parsed = JSON.parse(json) as Record<string, Object>;
      } catch (e) {
        this.getUIContext().getPromptAction().showToast({ message: '备份解析失败' });
        return;
      }
      const arr = (k: string): Array<Record<string, Object>> => {
        const v = parsed[k];
        return v === undefined || v === null ? [] : v as Array<Record<string, Object>>;
      };
      const tts = arr('timetables');
      const subs = arr('subjects');
      const evs = arr('events');
      await rdb.clearTable('timetable');
      await rdb.clearTable('subject');
      await rdb.clearTable('events');
      for (let i = 0; i < tts.length; i++) {
        await rdb.saveTimetable(ProfilePage.timetableFromJson(tts[i]));
      }
      for (let i = 0; i < subs.length; i++) {
        await rdb.saveSubject(ProfilePage.subjectFromJson(subs[i]));
      }
      for (let i = 0; i < evs.length; i++) {
        await rdb.saveEvent(ProfilePage.eventFromJson(evs[i]));
      }
      this.getUIContext().getPromptAction().showToast({ message: '已恢复 ' + tts.length.toString() + ' 课表 / ' +
        subs.length.toString() + ' 科目 / ' + evs.length.toString() + ' 事件' });
      this.summary = '恢复完成：' + tts.length.toString() + ' 课表 / ' +
        subs.length.toString() + ' 科目 / ' + evs.length.toString() + ' 事件';
    }).catch(() => {
    });
  }

  static timetableFromJson(r: Record<string, Object>): EasTimetable {
    const t: EasTimetable = new EasTimetable();
    t.id = ProfilePage.str(r, 'id');
    t.name = ProfilePage.str(r, 'name');
    t.code = ProfilePage.str(r, 'code');
    t.startTime = ProfilePage.num(r, 'startTime');
    t.endTime = ProfilePage.num(r, 'endTime');
    const st: string = ProfilePage.str(r, 'scheduleStructure');
    t.scheduleStructure = EasTimetable.decodeStructure(st);
    return t;
  }

  static subjectFromJson(r: Record<string, Object>): EasTermSubject {
    const s: EasTermSubject = new EasTermSubject();
    s.id = ProfilePage.str(r, 'id');
    s.timetableId = ProfilePage.str(r, 'timetableId');
    s.name = ProfilePage.str(r, 'name');
    s.type = ProfilePage.subjectType(ProfilePage.str(r, 'type'));
    s.field = ProfilePage.str(r, 'field');
    s.credit = ProfilePage.num(r, 'credit');
    s.school = ProfilePage.str(r, 'school');
    s.countInSPA = ProfilePage.num(r, 'countInSPA') !== 0;
    s.code = ProfilePage.str(r, 'code');
    s.key = ProfilePage.str(r, 'key');
    s.color = ProfilePage.num(r, 'color');
    return s;
  }

  static eventFromJson(r: Record<string, Object>): EasEventItem {
    const e: EasEventItem = new EasEventItem();
    e.id = ProfilePage.str(r, 'id');
    e.type = ProfilePage.eventType(ProfilePage.str(r, 'type'));
    e.name = ProfilePage.str(r, 'name');
    e.place = ProfilePage.str(r, 'place');
    e.teacher = ProfilePage.str(r, 'teacher');
    e.subjectId = ProfilePage.str(r, 'subjectId');
    e.timetableId = ProfilePage.str(r, 'timetableId');
    e.from = ProfilePage.num(r, 'from');
    e.to = ProfilePage.num(r, 'to');
    e.fromNumber = ProfilePage.num(r, 'fromNumber');
    e.lastNumber = ProfilePage.num(r, 'lastNumber');
    const c: number = ProfilePage.num(r, 'color');
    e.color = c !== 0 ? c : (e.type === EasEventType.EXAM ? 0xFFD93025 : 0xFF5C6BC0);
    return e;
  }

  private static str(r: Record<string, Object>, k: string): string {
    const v = r[k];
    return v === undefined || v === null ? '' : String(v);
  }

  private static num(r: Record<string, Object>, k: string): number {
    const v = r[k];
    if (v === undefined || v === null) {
      return 0;
    }
    const n: number = Number(v);
    return Number.isNaN(n) ? 0 : n;
  }

  private static eventType(s: string): EasEventType {
    if (s === 'EXAM') {
      return EasEventType.EXAM;
    }
    if (s === 'OTHER') {
      return EasEventType.OTHER;
    }
    if (s === 'TAG') {
      return EasEventType.TAG;
    }
    return EasEventType.CLASS;
  }

  private static subjectType(s: string): EasSubjectType {
    if (s === 'COM_B') {
      return EasSubjectType.COM_B;
    }
    if (s === 'OPT_A') {
      return EasSubjectType.OPT_A;
    }
    if (s === 'OPT_B') {
      return EasSubjectType.OPT_B;
    }
    if (s === 'MOOC') {
      return EasSubjectType.MOOC;
    }
    if (s === 'TAG') {
      return EasSubjectType.TAG;
    }
    return EasSubjectType.COM_A;
  }

  static campusOf(code: string): EasCampus {
    if (code === 'BENBU') {
      return EasCampus.BENBU;
    }
    if (code === 'WEIHAI') {
      return EasCampus.WEIHAI;
    }
    return EasCampus.SHENZHEN;
  }

  static campusLabel(c: EasCampus): string {
    if (c === EasCampus.BENBU) {
      return '本部';
    }
    if (c === EasCampus.WEIHAI) {
      return '威海';
    }
    return '深圳';
  }

  /* ─────────────── build() — Material 3 redesign ─────────────── */

  @Builder
  ActionItem(icon: string, label: string, labelColor: string, onClick: () => void) {
    Column() {
      Row() {
        Text(icon)
          .fontSize(20)
          .width(32)
          .textAlign(TextAlign.Center)
        Text(label)
          .fontSize(15)
          .fontColor(labelColor)
          .margin({ left: 12 })
          .layoutWeight(1)
        Text('›')
          .fontSize(20)
          .fontColor('#B0B4BA')
      }
      .width('100%')
      .height(52)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16 })
      .onClick(() => {
        onClick();
      })
    }
  }

  build() {
    Column() {
      // ── Header: Android-style light toolbar ──
      Row() {
        Text('‹')
          .fontSize(30)
          .fontColor('#1A1A1A')
          .fontWeight(FontWeight.Bold)
          .width(44)
          .height(44)
          .textAlign(TextAlign.Center)
          .borderRadius(20)
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
        Text('会话管理')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1A1A1A')
          .margin({ left: 4 })
        Blank()
      }
      .width('100%')
      .padding({ left: 8, right: 16, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor('#FFFFFF')
      .border({ width: { bottom: 1 }, color: '#EAECF0' })

      Scroll() {
        Column() {
          // ── User info card ──
          Row() {
            // Avatar circle
            Column() {
              Text(this.hasSession && this.userName.length > 0 ? this.userName.substring(0, 1) : '?')
                .fontSize(28)
                .fontColor('#FFFFFF')
                .fontWeight(FontWeight.Bold)
            }
            .width(64)
            .height(64)
            .borderRadius(32)
            .backgroundColor(this.hasSession ? '#3390EC' : '#AAB4C1')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)

            // User details
            Column() {
              if (this.hasSession && this.userName.length > 0) {
                Text(this.userName)
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1A1A1A')
                Text(this.userCampusLabel + (this.userStuId.length > 0 ? ' · ' + this.userStuId : ''))
                  .fontSize(13)
                  .fontColor('#808080')
                  .margin({ top: 4 })
                Text('会话代数 ' + this.sessionGen.toString())
                  .fontSize(12)
                  .fontColor('#B0B4BA')
                  .margin({ top: 2 })
              } else {
                Text('未登录')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1A1A1A')
                Text(this.userCampusLabel.length > 0 ? this.userCampusLabel + ' · 暂无会话' : '请先选择校区并登录')
                  .fontSize(13)
                  .fontColor('#B0B4BA')
                  .margin({ top: 4 })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 16 })
            .layoutWeight(1)
          }
          .width('100%')
          .padding(20)
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
          .margin({ top: 12, left: 16, right: 16 })

          // ── Campus selector pills ──
          Row({ space: 10 }) {
            Button('深圳')
              .fontSize(14)
              .height(36)
              .borderRadius(20)
              .backgroundColor(this.selectedCampus === 'SHENZHEN' ? '#3390EC' : '#FFFFFF')
              .fontColor(this.selectedCampus === 'SHENZHEN' ? '#FFFFFF' : '#808080')
              .border({ width: this.selectedCampus === 'SHENZHEN' ? 0 : 1,
                color: '#E0E0E0' })
              .padding({ left: 20, right: 20 })
              .onClick(() => {
                this.selectedCampus = 'SHENZHEN';
                this.refresh();
              })
            Button('本部')
              .fontSize(14)
              .height(36)
              .borderRadius(20)
              .backgroundColor(this.selectedCampus === 'BENBU' ? '#3390EC' : '#FFFFFF')
              .fontColor(this.selectedCampus === 'BENBU' ? '#FFFFFF' : '#808080')
              .border({ width: this.selectedCampus === 'BENBU' ? 0 : 1,
                color: '#E0E0E0' })
              .padding({ left: 20, right: 20 })
              .onClick(() => {
                this.selectedCampus = 'BENBU';
                this.refresh();
              })
            Button('威海')
              .fontSize(14)
              .height(36)
              .borderRadius(20)
              .backgroundColor(this.selectedCampus === 'WEIHAI' ? '#3390EC' : '#FFFFFF')
              .fontColor(this.selectedCampus === 'WEIHAI' ? '#FFFFFF' : '#808080')
              .border({ width: this.selectedCampus === 'WEIHAI' ? 0 : 1,
                color: '#E0E0E0' })
              .padding({ left: 20, right: 20 })
              .onClick(() => {
                this.selectedCampus = 'WEIHAI';
                this.refresh();
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 16, bottom: 8 })

          // ── Session detail card ──
          if (this.hasSession && this.detailRows.length > 0) {
            Column() {
              ForEach(this.detailRows, (row: string[], index: number) => {
                Row() {
                  Text(row[0])
                    .fontSize(13)
                    .fontColor('#808080')
                    .width(90)
                  Text(row[1])
                    .fontSize(14)
                    .fontColor('#1A1A1A')
                    .layoutWeight(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .maxLines(1)
                }
                .width('100%')
                .padding({ top: 10, bottom: 10, left: 16, right: 16 })

                if (index < this.detailRows.length - 1) {
                  Divider()
                    .color('#F0F0F0')
                    .margin({ left: 16, right: 16 })
                }
              })
            }
            .width('100%')
            .backgroundColor('#FFFFFF')
            .borderRadius(16)
            .margin({ top: 12, left: 16, right: 16 })
            .clip(true)
          } else if (!this.hasSession) {
            Column() {
              Text('该校区暂无会话')
                .fontSize(14)
                .fontColor('#B0B4BA')
              Text('回首页完成网页登录后即可查看')
                .fontSize(12)
                .fontColor('#B0B4BA')
                .margin({ top: 4 })
            }
            .width('100%')
            .padding(24)
            .backgroundColor('#FFFFFF')
            .borderRadius(16)
            .margin({ top: 12, left: 16, right: 16 })
            .alignItems(HorizontalAlign.Center)
          }

          // ── Action items card ──
          Column() {
            // 退出登录
            if (this.hasSession) {
              this.ActionItem('🚪', '退出登录', '#D93025', () => {
                this.logoutSelected();
              })
              Divider().color('#F0F0F0').margin({ left: 60, right: 16 })
            }

            // 清除全部数据
            this.ActionItem('🗑️', '清除全部数据', '#D93025', () => {
              this.clearAllLocal();
            })

            Divider().color('#F0F0F0').margin({ left: 60, right: 16 })

            // 导出备份
            this.ActionItem('📤', '导出备份', '#00796B', () => {
              this.exportLocalJson();
            })

            Divider().color('#F0F0F0').margin({ left: 60, right: 16 })

            // 从备份恢复
            this.ActionItem('📥', '从备份恢复', '#00796B', () => {
              this.importLocalJson();
            })
          }
          .width('100%')
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
          .margin({ top: 16, left: 16, right: 16 })
          .clip(true)

          // ── Footer version info ──
          Column() {
            Text('HitaNEXT · HITA 鸿蒙 NEXT')
              .fontSize(12)
              .fontColor('#B0B4BA')
            Text('v0.1.0')
              .fontSize(11)
              .fontColor('#B0B4BA')
              .margin({ top: 2 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 24, bottom: 32 })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F7FA')
  }
}
