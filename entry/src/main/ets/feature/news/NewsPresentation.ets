/**
 * 资讯列表的展示规则：来源名、头像简称与配色、语义化日期、标题去噪和标签提炼。
 * 规则参照 HITA Aura 的 NewsNoticeListView / CampusNoticePresentation，保持纯函数便于测试。
 */
import { EasCampus } from '../eas/EasSession';
import { NewsItem } from './NewsService';

const DAY_MS: number = 24 * 60 * 60 * 1000;

/** 头像渐变的上下两色，按来源关键词或稳定哈希选取。 */
const AVATAR_PALETTES: string[][] = [
  ['#408FF5', '#296BD6'], // 教务
  ['#29ADA8', '#1A858A'], // 教研、实验
  ['#F0756B', '#D1524D'], // 学生、团委
  ['#9470E6', '#704DC7'], // 科研
  ['#3DB87A', '#298F5C'], // 安全、总务、后勤
  ['#F29938', '#D67324'], // 研究生、招生
  ['#5C75E0', '#4257BD'], // 国际
  ['#E0619E', '#BD4280'], // 工会、党
  ['#C78F42', '#A36B2E'], // 财务、资产
  ['#6694B8', '#477094']  // 人事、其他
];

const AVATAR_RULES: string[][] = [
  ['教务'], ['教研', '实验'], ['学生', '团委'], ['科学', '科研'], ['安全', '总务', '后勤'],
  ['研究生', '招生'], ['国际', '外事'], ['工会', '党'], ['财务', '资产'], ['人力', '人事']
];

const NAME_SUFFIXES: string[] = ['办公室', '委员会', '工作部', '管理处', '教学部', '研究院', '中心', '学院', '学部',
  '处', '部', '院', '室', '会'];

const FORWARD_PREFIXES: string[] = ['(转发)', '（转发）', '[转发]', '【转发】', '转发：', '转发:'];

const SCHOOL_PREFIXES: string[] = ['哈尔滨工业大学（深圳）', '哈尔滨工业大学(深圳)', '哈尔滨工业大学（威海）',
  '哈尔滨工业大学(威海)'];

export class NewsRowModel {
  source: string = '';
  avatarText: string = '';
  avatarColors: string[] = AVATAR_PALETTES[0];
  title: string = '';
  /** 标题下方的灰色正文：博客摘要；通知没有摘要时为空。 */
  body: string = '';
  /** 标题前的小标签：【】标签、“转发”或博客首个标签。 */
  tag: string = '';
  date: string = '';
}

export class NewsPresentation {
  static row(item: NewsItem, blog: boolean, campus: EasCampus, now: number): NewsRowModel {
    const row: NewsRowModel = new NewsRowModel();
    row.date = NewsPresentation.semanticDate(item.date, now);
    if (blog) {
      // 博客的来源是作者；RSS 回退时 department 是作者列表，HTML 列表只给出 “HOA”。
      row.source = item.department.length > 0 && item.department !== 'HOA' ? item.department : 'HOA 博客';
      row.title = item.title;
      row.body = item.summary.length > 0 && item.summary !== item.title ? item.summary : '';
      row.tag = item.tags.length > 0 ? item.tags[0] : '';
    } else {
      row.source = item.department.length > 0 ? item.department : NewsPresentation.campusSource(campus);
      const cleaned: string[] = NewsPresentation.cleanTitle(item.title);
      row.title = cleaned[0];
      row.tag = cleaned[1] !== row.source ? cleaned[1] : '';
    }
    row.avatarText = NewsPresentation.avatarText(row.source);
    row.avatarColors = NewsPresentation.avatarColors(row.source);
    return row;
  }

  static campusSource(campus: EasCampus): string {
    if (campus === EasCampus.SHENZHEN) return '深圳校区';
    if (campus === EasCampus.WEIHAI) return '威海校区';
    return '今日哈工大';
  }

  /** 返回 [去噪后的标题, 标签]。标签取自开头的【】/[]，或转发前缀。 */
  static cleanTitle(raw: string): string[] {
    let title: string = raw.replace(/\s+/g, ' ').trim();
    let tag: string = '';
    for (const prefix of FORWARD_PREFIXES) {
      if (title.startsWith(prefix)) {
        tag = '转发';
        title = title.substring(prefix.length).trim();
        break;
      }
    }
    const bracket: RegExpExecArray | null = /^(?:【([^】]{2,12})】|\[([^\]]{2,12})\])\s*/.exec(title);
    if (bracket !== null) {
      const remainder: string = title.substring(bracket[0].length).trim();
      // 括号后不足 4 个字时括号本身就是标题，不拆。
      if (remainder.length >= 4) {
        tag = (bracket[1] !== undefined ? bracket[1] : bracket[2]).trim();
        title = remainder;
      }
    }
    for (const prefix of SCHOOL_PREFIXES) {
      if (title.startsWith(prefix) && title.length > prefix.length + 4) {
        title = title.substring(prefix.length).trim();
        break;
      }
    }
    return [title.length > 0 ? title : raw.trim(), tag];
  }

  /** 去掉常见机构后缀后取 1–4 个字；4 个字时分两行。 */
  static avatarText(source: string): string {
    let name: string = source.split('·')[0].split('、')[0].trim();
    // A leading Latin word ("HOA 博客", "justice") stays on one line: up to three letters fit
    // the avatar, longer words are cut to two. Mixing it with the Chinese rule split "HOA" in half.
    const latin: RegExpExecArray | null = /^[A-Za-z0-9]{2,}/.exec(name);
    if (latin !== null) {
      const word: string = latin[0].toUpperCase();
      return word.length <= 3 ? word : word.substring(0, 2);
    }
    for (const suffix of NAME_SUFFIXES) {
      if (name.endsWith(suffix) && name.length > suffix.length + 1) {
        name = name.substring(0, name.length - suffix.length);
        break;
      }
    }
    const chars: string[] = Array.from(name);
    if (chars.length === 0) return '?';
    if (chars.length <= 2) return chars.join('');
    if (chars.length === 3) return chars.slice(0, 2).join('');
    return chars[0] + chars[1] + '\n' + chars[2] + chars[3];
  }

  /** 两行汉字最小；三个字母也要在 46vp 的圆里单行放下。 */
  static avatarFontSize(text: string): number {
    if (text.includes('\n')) return 11;
    return Array.from(text).length >= 3 ? 13 : 15;
  }

  /** 同一来源始终同色：先按关键词，再用 FNV-1a 哈希。 */
  static avatarColors(source: string): string[] {
    for (let i: number = 0; i < AVATAR_RULES.length; i++) {
      if (AVATAR_RULES[i].some((word: string): boolean => source.includes(word))) {
        return AVATAR_PALETTES[i];
      }
    }
    let hash: number = 0x811c9dc5;
    for (let i: number = 0; i < source.length; i++) {
      hash ^= source.charCodeAt(i);
      hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    return AVATAR_PALETTES[hash % AVATAR_PALETTES.length];
  }

  /** "2026-10-23" → 今天 / 昨天 / 前天 / N天前 / 10月9日 / 2025年12月30日；其他写法原样返回。 */
  static semanticDate(text: string, now: number): string {
    const match: RegExpExecArray | null = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(text.trim());
    if (match === null) return text.trim();
    const year: number = Number(match[1]);
    const month: number = Number(match[2]);
    const day: number = Number(match[3]);
    const target: Date = new Date(year, month - 1, day);
    if (target.getMonth() !== month - 1 || target.getDate() !== day) return text.trim();
    const today: Date = new Date(now);
    const todayStart: number = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
    const diff: number = Math.round((todayStart - target.getTime()) / DAY_MS);
    if (diff === 0) return '今天';
    if (diff === 1) return '昨天';
    if (diff === 2) return '前天';
    if (diff >= 3 && diff <= 6) return diff.toString() + '天前';
    if (year === today.getFullYear()) return month.toString() + '月' + day.toString() + '日';
    return year.toString() + '年' + month.toString() + '月' + day.toString() + '日';
  }
}
