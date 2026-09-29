/** Selects the user's imported timetable while keeping the local demo as a fallback. */
import { RdbHelper } from '../../../common/db/RdbHelper';
import { EasTimetable } from '../../../common/model/timetable/TimetableModels';
import { TimetableLocalDemo } from './TimetableLocalDemo';

export class TimetableResolver {
  static isReal(timetable: EasTimetable): boolean {
    return timetable.code !== TimetableLocalDemo.DEMO_CODE;
  }

  static async getReal(rdb: RdbHelper): Promise<EasTimetable | undefined> {
    const all: EasTimetable[] = await rdb.getTimetables();
    for (let i: number = 0; i < all.length; i++) {
      if (TimetableResolver.isReal(all[i])) {
        return all[i];
      }
    }
    return undefined;
  }

  static async getForDisplay(rdb: RdbHelper): Promise<EasTimetable | undefined> {
    const real: EasTimetable | undefined = await TimetableResolver.getReal(rdb);
    if (real !== undefined) {
      return real;
    }
    return await rdb.getTimetableByEasCode(TimetableLocalDemo.DEMO_CODE);
  }
}
