import { EasSubjectType, EasTermSubject } from '../../common/model/timetable/TimetableModels';

export class CreditField {
  name: string = '';
  credits: number = 0;
}

export class LocalCreditCategory {
  type: EasSubjectType = EasSubjectType.COM_A;
  credits: number = 0;
  goal: number = 0;
  subjects: EasTermSubject[] = [];
  fields: CreditField[] = [];
}

export class LocalCreditSummary {
  credits: number = 0;
  count: number = 0;
  spaCredits: number = 0;
  nonSpaCredits: number = 0;
  categories: LocalCreditCategory[] = [];
}

export class CreditIdentity {
  studentNumber: string = '';
  recordId: string = '';
  studentType: string = '';
  grade: string = '';
}

export class CreditContext extends CreditIdentity {
  planId: string = '';
}

export class CreditRequirement {
  id: string = '';
  name: string = '';
  direction: string = '';
  language: string = '';
  nature: string = '';
  required: number = 0;
  completed: number = 0;
  remaining: number = 0;
  hours: number | undefined = undefined;
  creditedMooc: number = 0;
  earnedMooc: number = 0;
  passed: boolean = false;
}

export class CreditGroupCourse {
  code: string = '';
  name: string = '';
  credits: number = 0;
  term: string = '';
  nature: string = '';
  completed: boolean = false;
}

export class CreditGroup {
  id: string = '';
  parentId: string = '';
  name: string = '';
  depth: number = 0;
  required: number | undefined = undefined;
  completed: number = 0;
  requiredCourses: number | undefined = undefined;
  completedCourses: number = 0;
  passed: boolean = false;
  courses: CreditGroupCourse[] = [];
  hasChildren: boolean = false;
}

export class CreditCourseRecord {
  id: string = '';
  term: string = '';
  code: string = '';
  name: string = '';
  credits: number = 0;
  score: string = '';
  teacher: string = '';
  nature: string = '';
  category: string = '';
}

export class OfficialCreditProgress {
  // Missing summary data must not be displayed as zero completed credits.
  required: number | undefined = undefined;
  completed: number | undefined = undefined;
  remaining: number | undefined = undefined;
  requiredCourses: number | undefined = undefined;
  completedCourses: number | undefined = undefined;
  remainingCourses: number | undefined = undefined;
  average: number | undefined = undefined;
  rank: number | undefined = undefined;
  cohortSize: number | undefined = undefined;
  term: string = '';
  categories: CreditRequirement[] = [];
  groups: CreditGroup[] = [];
  records: CreditCourseRecord[] = [];
  notices: string[] = [];
  context: CreditContext = new CreditContext();

  snapshot(): OfficialCreditProgress {
    const result = new OfficialCreditProgress();
    result.required = this.required;
    result.completed = this.completed;
    result.remaining = this.remaining;
    result.requiredCourses = this.requiredCourses;
    result.completedCourses = this.completedCourses;
    result.remainingCourses = this.remainingCourses;
    result.average = this.average;
    result.rank = this.rank;
    result.cohortSize = this.cohortSize;
    result.term = this.term;
    result.categories = this.categories.slice();
    result.groups = this.groups.slice();
    result.records = this.records.slice();
    result.notices = this.notices.slice();
    result.context = this.context;
    return result;
  }
}
