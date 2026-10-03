/**
 * EasSessionStore.ets — EAS 会话持久化（ArkTS preferences，对应蓝本 §4.4 简化版）。
 *
 * 蓝本建议 RDB 表 eas_session + HUKS 加密（后续升级）；M1 先用 preferences 落 JSON，
 * 敏感字段（cookie/token）在加密接入前以文档标注 TODO。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { EasCampus, EasSession } from './EasSession';

const STORE_NAME: string = 'hitanext_store';
const SESSION_PREFIX: string = 'eas_session_';
const LAST_CAMPUS_KEY: string = 'eas_last_campus';

export class EasSessionStore {
  private static instance: EasSessionStore | undefined = undefined;
  private store: preferences.Preferences | undefined = undefined;
  private context: common.Context | undefined = undefined;

  static getInstance(): EasSessionStore {
    if (EasSessionStore.instance === undefined) {
      EasSessionStore.instance = new EasSessionStore();
    }
    return EasSessionStore.instance;
  }

  /** 必须在 Ability/UIAbility 上下文可用后调用一次。 */
  async init(context: common.Context): Promise<void> {
    this.context = context;
    try {
      this.store = await preferences.getPreferences(context, { name: STORE_NAME });
    } catch (e) {
      this.store = undefined;
    }
  }

  private keyOf(campus: EasCampus): string {
    return SESSION_PREFIX + campus.toString();
  }

  /** 读取某校区会话；无则返回 undefined。 */
  async load(campus: EasCampus): Promise<EasSession | undefined> {
    if (this.store === undefined) {
      return undefined;
    }
    try {
      const raw: preferences.ValueType = await this.store.get(this.keyOf(campus), '');
      const text: string = raw === undefined || raw === null ? '' : String(raw);
      if (text.length === 0) {
        return undefined;
      }
      return EasSession.decode(text);
    } catch (e) {
      return undefined;
    }
  }

  /** 保存某校区会话（sessionGeneration 自增由调用方控制，这里只落盘）。 */
  async save(session: EasSession): Promise<void> {
    if (this.store === undefined) {
      return;
    }
    try {
      await this.store.put(this.keyOf(session.campus), session.encode());
      await this.store.put(LAST_CAMPUS_KEY, session.campus.toString());
      await this.store.flush();
    } catch (e) {
    }
  }

  /** 最近一次完成登录的校区，用于多校区并存时选择正确的数据会话。 */
  async loadLastCampus(): Promise<EasCampus | undefined> {
    if (this.store === undefined) {
      return undefined;
    }
    try {
      const raw: preferences.ValueType = await this.store.get(LAST_CAMPUS_KEY, '');
      const value: string = raw === undefined || raw === null ? '' : String(raw);
      if (value === EasCampus.SHENZHEN.toString()) {
        return EasCampus.SHENZHEN;
      }
      if (value === EasCampus.BENBU.toString()) {
        return EasCampus.BENBU;
      }
      if (value === EasCampus.WEIHAI.toString()) {
        return EasCampus.WEIHAI;
      }
    } catch (e) {
    }
    return undefined;
  }

  /** 清除某校区会话（退出登录）。 */
  async clear(campus: EasCampus): Promise<void> {
    if (this.store === undefined) {
      return;
    }
    try {
      await this.store.delete(this.keyOf(campus));
      const last: EasCampus | undefined = await this.loadLastCampus();
      if (last === campus) {
        await this.store.delete(LAST_CAMPUS_KEY);
      }
      await this.store.flush();
    } catch (e) {
    }
  }
}
