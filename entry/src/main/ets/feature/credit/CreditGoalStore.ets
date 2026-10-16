import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { EasSubjectType } from '../../common/model/timetable/TimetableModels';
import { CREDIT_TYPES } from './LocalCreditData';

export class CreditGoalStore {
  private store: preferences.Preferences | undefined = undefined;

  async init(context: common.Context): Promise<void> {
    this.store = await preferences.getPreferences(context, { name: 'hita_credit_goals' });
  }

  async load(): Promise<Map<string, number>> {
    const goals = new Map<string, number>();
    if (this.store === undefined) throw new Error('学分目标读取失败');
    for (const type of CREDIT_TYPES) {
      const value = Number(await this.store.get(type, 0));
      if (Number.isFinite(value) && value > 0) goals.set(type, value);
    }
    return goals;
  }

  async save(type: EasSubjectType, credits: number): Promise<void> {
    if (this.store === undefined || CREDIT_TYPES.indexOf(type) < 0 ||
      !Number.isFinite(credits) || credits < 0 || credits > 1000) {
      throw new Error('请输入 0 到 1000 之间的学分');
    }
    if (credits === 0) await this.store.delete(type);
    else await this.store.put(type, credits);
    await this.store.flush();
  }
}
