/**
 * RdbHelper.ets — 本地 RDB（对应 HITA_X AppDatabase v1：timetable/subject/events；Room → relationalStore）。
 *
 * 对齐：
 *  - AppDatabase.kt（三实体，库名 "hita"）
 *  - TypeConverters.kt（Timestamp→Long、枚举→name 文本、scheduleStructure→JSON）
 *  - TimetableDao / SubjectDao / EventItemDao（同步方法面，LiveData 观察由页面状态层承担）
 * Event timestamps use fromTime/toTime instead of SQLite reserved words so
 * ValuesBucket inserts work consistently on HarmonyOS devices.
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { relationalStore } from '@kit.ArkData';
import {
  EasEventItem,
  EasEventType,
  EasSubjectColor,
  EasSubjectType,
  EasTermSubject,
  EasTimeInDay,
  EasTimePeriodInDay,
  EasTimetable
} from '../model/timetable/TimetableModels';
import { normalizeHtmlSpaces } from '../util/HtmlSpaces';

// The first prototype shipped a different schema under this name.  Use a
// versioned store so an upgrade cannot keep an incompatible old table layout.
const DB_NAME: string = 'hita_next_v3.db';
const DOMAIN: number = 0x0000;
const TAG: string = 'HitaRdb';

const CREATE_TIMETABLE: string =
  'CREATE TABLE IF NOT EXISTS timetable (' +
  'id TEXT PRIMARY KEY, name TEXT, code TEXT, startTime INTEGER NOT NULL, ' +
  'endTime INTEGER NOT NULL, createdAt INTEGER NOT NULL, scheduleStructure TEXT NOT NULL)';

const CREATE_SUBJECT: string =
  'CREATE TABLE IF NOT EXISTS subject (' +
  'id TEXT PRIMARY KEY, timetableId TEXT NOT NULL, name TEXT NOT NULL, type TEXT NOT NULL, ' +
  'field TEXT, credit REAL NOT NULL, school TEXT, countInSPA INTEGER NOT NULL, ' +
  'code TEXT, key TEXT, createdAt INTEGER NOT NULL, color INTEGER NOT NULL)';

const CREATE_EVENTS: string =
  'CREATE TABLE IF NOT EXISTS events (' +
  'id TEXT PRIMARY KEY, type TEXT NOT NULL, name TEXT NOT NULL, place TEXT, teacher TEXT, ' +
  'subjectId TEXT NOT NULL, timetableId TEXT NOT NULL, fromTime INTEGER NOT NULL, toTime INTEGER NOT NULL, ' +
  'fromNumber INTEGER NOT NULL, lastNumber INTEGER NOT NULL, createdAt INTEGER NOT NULL)';

export class RdbHelper {
  private static instance: RdbHelper | undefined = undefined;
  private store: relationalStore.RdbStore | undefined = undefined;

  static getInstance(): RdbHelper {
    if (RdbHelper.instance === undefined) {
      RdbHelper.instance = new RdbHelper();
    }
    return RdbHelper.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.store !== undefined) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    try {
      this.store = await relationalStore.getRdbStore(context, config);
    } catch (e) {
      throw new Error('RdbHelper init failed');
    }
    await this.execSql(CREATE_TIMETABLE);
    await this.execSql(CREATE_SUBJECT);
    await this.execSql(CREATE_EVENTS);
    await this.repairLegacyWeihaiTimetables();
  }

  private s(): relationalStore.RdbStore {
    if (this.store === undefined) {
      throw new Error('RdbHelper 未初始化：请先 init(context)');
    }
    return this.store;
  }

  // —— 异常安全助手（函数 may throw → 就地吞掉/返回 null）——
  private async del(pred: relationalStore.RdbPredicates): Promise<void> {
    try {
      await this.s().delete(pred);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'delete failed %{public}s', String(e));
      throw new Error(String(e));
    }
  }

  private async ins(table: string, bucket: relationalStore.ValuesBucket): Promise<void> {
    try {
      const rowId: number = await this.s().insert(table, bucket);
      if (rowId < 0) {
        throw new Error('insert returned ' + rowId.toString());
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'insert table=%{public}s failed %{public}s', table, String(e));
      throw new Error(String(e));
    }
  }

  private async upd(values: relationalStore.ValuesBucket, pred: relationalStore.RdbPredicates): Promise<void> {
    try {
      await this.s().update(values, pred);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'update failed %{public}s', String(e));
      throw new Error(String(e));
    }
  }

  private async qry(pred: relationalStore.RdbPredicates,
    columns?: string[]): Promise<relationalStore.ResultSet | null> {
    try {
      if (columns === undefined || columns === null) {
        return await this.s().query(pred);
      }
      return await this.s().query(pred, columns);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'query failed %{public}s', String(e));
      return null;
    }
  }

  private async execSql(sql: string): Promise<void> {
    try {
      await this.s().executeSql(sql);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'execSql failed %{public}s', String(e));
      throw new Error(String(e));
    }
  }

  // ------------------------------------------------------------------
  // 通用
  // ------------------------------------------------------------------

  async clearTable(table: string): Promise<void> {
    await this.del(new relationalStore.RdbPredicates(table));
  }

  private async replaceRow(table: string, bucket: relationalStore.ValuesBucket, pkColumn: string,
    pkValue: string): Promise<void> {
    await this.del(new relationalStore.RdbPredicates(table).equalTo(pkColumn, pkValue));
    await this.ins(table, bucket);
  }

  /** 修复早期版本把威海误存为本部作息的本地课表。 */
  private async repairLegacyWeihaiTimetables(): Promise<void> {
    const timetables: EasTimetable[] = await this.getTimetables();
    const correct: EasTimePeriodInDay[] = EasTimetable.getWeihaiTimeStructure();
    for (let i: number = 0; i < timetables.length; i++) {
      const timetable: EasTimetable = timetables[i];
      if (!timetable.code.startsWith('WEIHAI:') || !RdbHelper.isLegacyBenbuSchedule(timetable)) {
        continue;
      }
      const events: EasEventItem[] = await this.getEventsOfTimetable(timetable.id);
      timetable.scheduleStructure = correct;
      await this.saveTimetable(timetable);
      for (let j: number = 0; j < events.length; j++) {
        const event: EasEventItem = events[j];
        if (event.type !== EasEventType.CLASS || event.fromNumber < 1 || event.lastNumber < event.fromNumber ||
          event.lastNumber > correct.length) {
          continue;
        }
        const oldDate: Date = new Date(event.from);
        const dayStart: number = new Date(oldDate.getFullYear(), oldDate.getMonth(), oldDate.getDate(),
          0, 0, 0, 0).getTime();
        event.from = dayStart + correct[event.fromNumber - 1].from.toMills();
        event.to = dayStart + correct[event.lastNumber - 1].to.toMills();
        await this.saveEvent(event);
      }
      hilog.info(DOMAIN, TAG, 'repaired legacy Weihai timetable=%{public}s events=%{public}d',
        timetable.id, events.length);
    }
  }

  private static isLegacyBenbuSchedule(timetable: EasTimetable): boolean {
    if (timetable.scheduleStructure.length !== 12) {
      return false;
    }
    const first: EasTimePeriodInDay = timetable.scheduleStructure[0];
    const sixth: EasTimePeriodInDay = timetable.scheduleStructure[5];
    const seventh: EasTimePeriodInDay = timetable.scheduleStructure[6];
    return first.from.equals(new EasTimeInDay(8, 0)) && first.to.equals(new EasTimeInDay(8, 50)) &&
      sixth.from.equals(new EasTimeInDay(14, 25)) && sixth.to.equals(new EasTimeInDay(15, 15)) &&
      seventh.from.equals(new EasTimeInDay(15, 25)) && seventh.to.equals(new EasTimeInDay(16, 15));
  }

  // ------------------------------------------------------------------
  // timetable
  // ------------------------------------------------------------------

  async saveTimetable(t: EasTimetable): Promise<void> {
    const b: relationalStore.ValuesBucket = {
      'id': t.id,
      'name': t.name,
      'code': t.code,
      'startTime': t.startTime,
      'endTime': t.endTime,
      'createdAt': t.createdAt,
      'scheduleStructure': EasTimetable.encodeStructure(t.scheduleStructure)
    };
    await this.replaceRow('timetable', b, 'id', t.id);
  }

  /** 按 -startTime 排序的全量课表。 */
  async getTimetables(): Promise<EasTimetable[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('timetable');
    pred.orderByDesc('startTime');
    const rs: relationalStore.ResultSet | null = await this.qry(pred);
    return RdbHelper.readRows(rs, (col: (name: string) => ValueGetter) => {
      const t: EasTimetable = new EasTimetable();
      t.id = col('id').str();
      t.name = col('name').str();
      t.code = col('code').str();
      t.startTime = col('startTime').num();
      t.endTime = col('endTime').num();
      t.createdAt = col('createdAt').num();
      t.scheduleStructure = EasTimetable.decodeStructure(col('scheduleStructure').str());
      return t;
    });
  }

  async getTimetableById(id: string): Promise<EasTimetable | undefined> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('timetable');
    pred.equalTo('id', id);
    return RdbHelper.firstRow(await this.qry(pred), (col: (name: string) => ValueGetter) => {
      const t: EasTimetable = new EasTimetable();
      t.id = col('id').str();
      t.name = col('name').str();
      t.code = col('code').str();
      t.startTime = col('startTime').num();
      t.endTime = col('endTime').num();
      t.createdAt = col('createdAt').num();
      t.scheduleStructure = EasTimetable.decodeStructure(col('scheduleStructure').str());
      return t;
    });
  }

  async getTimetableByEasCode(easCode: string): Promise<EasTimetable | undefined> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('timetable');
    pred.equalTo('code', easCode);
    return RdbHelper.firstRow(await this.qry(pred), (col: (name: string) => ValueGetter) => {
      const t: EasTimetable = new EasTimetable();
      t.id = col('id').str();
      t.name = col('name').str();
      t.code = col('code').str();
      t.startTime = col('startTime').num();
      t.endTime = col('endTime').num();
      t.createdAt = col('createdAt').num();
      t.scheduleStructure = EasTimetable.decodeStructure(col('scheduleStructure').str());
      return t;
    });
  }

  async deleteTimetablesInIds(ids: string[]): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('timetable');
    pred.in('id', ids);
    await this.del(pred);
  }

  /** 删除课表以及其科目、课程事件，避免留下无法再访问的孤立数据。 */
  async deleteTimetablesCascade(ids: string[]): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    await this.del(new relationalStore.RdbPredicates('events').in('timetableId', ids));
    await this.del(new relationalStore.RdbPredicates('subject').in('timetableId', ids));
    await this.deleteTimetablesInIds(ids);
  }

  // ------------------------------------------------------------------
  // subject
  // ------------------------------------------------------------------

  async saveSubject(s: EasTermSubject): Promise<void> {
    const b: relationalStore.ValuesBucket = {
      'id': s.id,
      'timetableId': s.timetableId,
      'name': s.name,
      'type': s.type.toString(),
      'field': s.field,
      'credit': s.credit,
      'school': s.school,
      'countInSPA': s.countInSPA ? 1 : 0,
      'code': s.code,
      'key': s.key,
      'createdAt': s.createdAt,
      'color': s.color
    };
    await this.replaceRow('subject', b, 'id', s.id);
  }

  /** 某课表科目，按 credit 降序（对应 SubjectDao.getSubjects）。 */
  async getSubjectsOfTimetable(timetableId: string): Promise<EasTermSubject[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('subject');
    pred.equalTo('timetableId', timetableId);
    pred.orderByDesc('credit');
    const rs: relationalStore.ResultSet | null = await this.qry(pred);
    return RdbHelper.readRows(rs, (col: (name: string) => ValueGetter) => {
      const s: EasTermSubject = new EasTermSubject();
      s.id = col('id').str();
      s.timetableId = col('timetableId').str();
      s.name = col('name').str();
      s.type = RdbHelper.subjectTypeOf(col('type').str());
      s.field = col('field').str();
      s.credit = col('credit').numD();
      s.school = col('school').str();
      s.countInSPA = col('countInSPA').num() !== 0;
      s.code = col('code').str();
      s.key = col('key').str();
      s.createdAt = col('createdAt').num();
      s.color = col('color').num();
      return s;
    });
  }

  /** 指定科目 id 的 (id,color) 投影（对应 SubjectDao.getSubjectColorsWithId）。 */
  async getSubjectColors(ids: string[]): Promise<EasSubjectColor[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('subject');
    pred.in('id', ids);
    const rs: relationalStore.ResultSet | null = await this.qry(pred, ['id', 'color']);
    return RdbHelper.readRows(rs, (col: (name: string) => ValueGetter) => {
      const c: EasSubjectColor = new EasSubjectColor();
      c.id = col('id').str();
      c.color = col('color').num();
      return c;
    });
  }

  async changeSubjectColor(id: string, color: number): Promise<void> {
    await this.upd({ 'color': color },
      new relationalStore.RdbPredicates('subject').equalTo('id', id));
  }

  // ------------------------------------------------------------------
  // events
  // ------------------------------------------------------------------

  async saveEvent(e: EasEventItem): Promise<void> {
    await this.replaceRow('events', RdbHelper.eventValues(e), 'id', e.id);
  }

  /** Edit in place: failed writes must not remove or recreate an existing event. */
  async updateEvent(e: EasEventItem): Promise<void> {
    try {
      const count: number = await this.s().update(RdbHelper.eventValues(e),
        new relationalStore.RdbPredicates('events').equalTo('id', e.id));
      if (count !== 1) {
        throw new Error('Event no longer exists');
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'update event failed %{public}s', String(e));
      throw new Error(String(e));
    }
  }

  private static eventValues(e: EasEventItem): relationalStore.ValuesBucket {
    return {
      'id': e.id,
      'type': e.type.toString(),
      'name': e.name,
      'place': e.place,
      'teacher': e.teacher,
      'subjectId': e.subjectId,
      'timetableId': e.timetableId,
      'fromTime': e.from,
      'toTime': e.to,
      'fromNumber': e.fromNumber,
      'lastNumber': e.lastNumber,
      'createdAt': e.createdAt
    };
  }

  /** 区间内事件（对应 getEventsDuringSync：from/to 四向包含）。 */
  async getEventsDuring(fromT: number, toT: number): Promise<EasEventItem[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('events');
    pred.greaterThanOrEqualTo('fromTime', fromT).lessThanOrEqualTo('fromTime', toT)
      .greaterThanOrEqualTo('toTime', fromT).lessThanOrEqualTo('toTime', toT);
    pred.orderByAsc('fromTime');
    return RdbHelper.readRows(await this.qry(pred), RdbHelper.eventMapper);
  }

  /** from >= fromT，升序取前 limit 条（对应 getEventsAfter）。 */
  async getEventsAfter(fromT: number, limit: number): Promise<EasEventItem[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('events');
    pred.greaterThanOrEqualTo('fromTime', fromT);
    pred.orderByAsc('fromTime');
    pred.limitAs(limit);
    return RdbHelper.readRows(await this.qry(pred), RdbHelper.eventMapper);
  }

  /** 某课表全部事件（对应 getEventsOfTimetableSync）。 */
  async getEventsOfTimetable(timetableId: string): Promise<EasEventItem[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('events');
    pred.equalTo('timetableId', timetableId);
    pred.orderByAsc('fromTime');
    return RdbHelper.readRows(await this.qry(pred), RdbHelper.eventMapper);
  }

  async getClassesOfSubject(subjectId: string): Promise<EasEventItem[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('events');
    pred.equalTo('subjectId', subjectId);
    pred.orderByAsc('fromTime');
    return RdbHelper.readRows(await this.qry(pred), RdbHelper.eventMapper);
  }

  /** 删除某课表的课程类事件（对应 deleteCourseFromTimetable）。 */
  async deleteCourseFromTimetable(timetableId: string): Promise<void> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('events');
    pred.equalTo('timetableId', timetableId);
    pred.in('type', [EasEventType.CLASS.toString(), EasEventType.EXAM.toString()]);
    await this.del(pred);
  }

  /** 单条事件读取。 */
  async getEventById(id: string): Promise<EasEventItem | undefined> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('events');
    pred.equalTo('id', id);
    return RdbHelper.firstRow(await this.qry(pred), RdbHelper.eventMapper);
  }

  /** 删除单条事件。 */
  async deleteEvent(id: string): Promise<void> {
    await this.del(new relationalStore.RdbPredicates('events').equalTo('id', id));
  }

  /** 删除某科目全部课程事件。 */
  async deleteEventsOfSubject(subjectId: string): Promise<void> {
    await this.del(new relationalStore.RdbPredicates('events').equalTo('subjectId', subjectId));
  }

  /** 删除科目。 */
  async deleteSubject(id: string): Promise<void> {
    await this.del(new relationalStore.RdbPredicates('subject').equalTo('id', id));
  }

  /** 删除某课表全部事件（对应 deleteEventsFromTimetablesSync 单表实现）。 */
  async deleteEventsOfTimetable(timetableId: string): Promise<void> {
    await this.del(new relationalStore.RdbPredicates('events').equalTo('timetableId', timetableId));
  }

  // ------------------------------------------------------------------
  // 私有：行 → 模型
  // ------------------------------------------------------------------

  private static eventMapper(col: (name: string) => ValueGetter): EasEventItem {
    const e: EasEventItem = new EasEventItem();
    e.id = col('id').str();
    e.type = RdbHelper.eventTypeOf(col('type').str());
    e.name = col('name').str();
    e.place = col('place').str();
    if (e.type === EasEventType.CLASS) {
      // Also clean placeholders in courses imported by earlier app versions.
      e.place = normalizeHtmlSpaces(e.place);
    }
    e.teacher = col('teacher').str();
    e.subjectId = col('subjectId').str();
    e.timetableId = col('timetableId').str();
    e.from = col('fromTime').num();
    e.to = col('toTime').num();
    e.fromNumber = col('fromNumber').num();
    e.lastNumber = col('lastNumber').num();
    e.createdAt = col('createdAt').num();
    return e;
  }

  private static eventTypeOf(s: string): EasEventType {
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

  private static subjectTypeOf(s: string): EasSubjectType {
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

  private static readRows<T>(rs: relationalStore.ResultSet | null,
    mapper: (col: (name: string) => ValueGetter) => T): T[] {
    const out: T[] = [];
    if (rs === null || rs === undefined) {
      return out;
    }
    try {
      while (rs.goToNextRow()) {
        const col = (name: string): ValueGetter => {
          return new ValueGetter(rs, name);
        };
        out.push(mapper(col));
      }
    } catch (e) {
    } finally {
      try {
        rs.close();
      } catch (e) {
      }
    }
    return out;
  }

  private static firstRow<T>(rs: relationalStore.ResultSet | null,
    mapper: (col: (name: string) => ValueGetter) => T): T | undefined {
    if (rs === null || rs === undefined) {
      return undefined;
    }
    try {
      if (rs.goToNextRow()) {
        const col = (name: string): ValueGetter => {
          return new ValueGetter(rs, name);
        };
        return mapper(col);
      }
      return undefined;
    } catch (e) {
      return undefined;
    } finally {
      try {
        rs.close();
      } catch (e) {
      }
    }
  }
}

/** ResultSet 单元格安全读取器。 */
class ValueGetter {
  private rs: relationalStore.ResultSet;
  private name: string;

  constructor(rs: relationalStore.ResultSet, name: string) {
    this.rs = rs;
    this.name = name;
  }

  str(): string {
    try {
      const idx: number = this.rs.getColumnIndex(this.name);
      const v = this.rs.getString(idx);
      return v === undefined || v === null ? '' : v;
    } catch (e) {
      return '';
    }
  }

  num(): number {
    try {
      const idx: number = this.rs.getColumnIndex(this.name);
      const v = this.rs.getLong(idx);
      return v === undefined || v === null ? 0 : Number(v);
    } catch (e) {
      return 0;
    }
  }

  /** 小数（REAL 列用 getDouble）。 */
  numD(): number {
    try {
      const idx: number = this.rs.getColumnIndex(this.name);
      const v = this.rs.getDouble(idx);
      return v === undefined || v === null ? 0 : Number(v);
    } catch (e) {
      return 0;
    }
  }
}
