/**
 * ScorePage.ets — 成绩查询（HITA_X ui/eas/score → ArkUI）。
 *
 * 数据面：EasDataProvider（EasApiClient + 深圳 JSON 解析，已就位）。
 * 深圳真链路使用网页登录会话 Cookie：
 *  - 无会话 → 提示先去登录；
 *  - 有会话 → "真实查询"请求深圳教务成绩接口；
 *  - "载入样例成绩(离线)" → 用解析器内置样例填充表格，预览成绩页 UI。
 * 网络返回与离线样例使用同一张表格渲染。
 */
import { common } from '@kit.AbilityKit';
import { EasCampus, EasSession } from '../feature/eas/EasSession';
import { EasSessionStore } from '../feature/eas/EasSessionStore';
import { EasDataProvider } from '../feature/eas/EasDataProvider';
import { parseShenzhenWebScores, SHENZHEN_SCORES_SAMPLE } from '../feature/eas/data/ShenzhenWebScores';
import { EasCourseScoreItem, EasTermItem } from '../feature/eas/model/EasModels';
import { EasApiClient } from '../feature/eas/EasApiClient';

@Entry
@Component
struct ScorePage {
  @State modeText: string = '（未选择）';
  @State msg: string = '';
  @State scores: EasCourseScoreItem[] = [];
  @State loading: boolean = false;
  private session: EasSession | undefined = undefined;
  private sampleTerm: EasTermItem = new EasTermItem();

  async aboutToAppear(): Promise<void> {
    this.sampleTerm.yearName = '2023-2024';
    this.sampleTerm.termName = '-1';
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    await EasSessionStore.getInstance().init(ctx);
    // 依次找深圳/本部/威海的可用会话
    const order: EasCampus[] = [EasCampus.SHENZHEN, EasCampus.BENBU, EasCampus.WEIHAI];
    for (let i = 0; i < order.length; i++) {
      const s: EasSession | undefined = await EasSessionStore.getInstance().load(order[i]);
      if (s !== undefined && s.isLogin()) {
        this.session = s;
        break;
      }
    }
    if (this.session !== undefined) {
      this.modeText = '会话：' + this.session.campus.toString() +
        '（cookies=' + this.session.webCookies.size.toString() + '）';
      if (this.session.campus === EasCampus.SHENZHEN && this.session.webBaseUrl.length > 0) {
        this.modeText += '\nbase=' + this.session.webBaseUrl;
      }
    } else {
      this.modeText = '（无会话：请先在首页完成网页登录）';
    }
  }

  /** 深圳真链路：需要网页登录会话 Cookie。 */
  async queryReal(): Promise<void> {
    if (this.session === undefined) {
      this.msg = '尚无会话：请先在首页登录';
      return;
    }
    this.loading = true;
    this.msg = '正在查询…';
    try {
      const provider: EasDataProvider = new EasDataProvider(new EasApiClient());
      const terms: EasTermItem[] = await provider.getAllTerms(this.session);
      const term: EasTermItem = terms.length > 0 ? terms[0] : this.sampleTerm;
      const result = await provider.getPersonalScores(this.session, term);
      if (result.ok) {
        this.scores = result.items;
        this.modeText = this.session.campus.toString() + ' · ' + term.name;
        this.msg = '共 ' + result.items.length.toString() + ' 条成绩（code=' +
          result.code.toString() + ' msg=' + result.msg + '）';
      } else {
        this.msg = result.msg;
      }
    } catch (e) {
      this.msg = (e as Error).message;
    } finally {
      this.loading = false;
    }
  }

  /** 离线样例：验证解析+预览成绩表格。 */
  loadSample(): void {
    const parsed = parseShenzhenWebScores(SHENZHEN_SCORES_SAMPLE, this.sampleTerm);
    if (parsed === undefined) {
      this.msg = '样例解析失败';
      return;
    }
    this.scores = parsed.list;
    this.modeText = '深圳样例成绩（离线）· ' + this.sampleTerm.name;
    this.msg = '共 ' + parsed.list.length.toString() + ' 条成绩（code=' + parsed.code.toString() +
      ' msg=' + parsed.msg + '）';
  }

  build() {
    Column() {
      // ── Header Bar ──
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

        Text('成绩查询')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
          .layoutWeight(1)
          .margin({ left: 4 })

        Text('真实查询')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#3390EC')
          .height(32)
          .padding({ left: 12, right: 12 })
          .borderRadius(16)
          .backgroundColor('#EBF4FC')
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.queryReal();
          })

        Text('载入样例')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#667085')
          .height(32)
          .padding({ left: 12, right: 12 })
          .borderRadius(16)
          .backgroundColor('#F2F4F7')
          .textAlign(TextAlign.Center)
          .margin({ left: 8 })
          .onClick(() => {
            this.loadSample();
          })
      }
      .width('100%')
      .padding({ left: 8, right: 12, top: 8, bottom: 8 })
      .backgroundColor('#FFFFFF')
      .border({ width: { bottom: 1 }, color: '#EAECF0' })
      .alignItems(VerticalAlign.Center)

      // ── Status info bar ──
      Column() {
        Text(this.modeText)
          .fontSize(12)
          .fontColor('#808080')
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.msg.length > 0) {
          Text(this.msg)
            .fontSize(12)
            .fontColor('#2E7D32')
            .width('100%')
            .margin({ top: 4 })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 8 })
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 4, color: '#0A000000', offsetY: 1 })

      // ── Content area ──
      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color('#3390EC')
          Text('正在查询…')
            .fontSize(14)
            .fontColor('#808080')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.scores.length === 0) {
        Column() {
          Text('◉')
            .fontSize(48)
            .fontColor('#B7C7D9')
            .margin({ bottom: 12 })
          Text('暂无成绩数据')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1A1A')
            .margin({ bottom: 8 })
          Text('点击"载入样例"预览离线数据\n或"真实查询"获取网络成绩')
            .fontSize(13)
            .fontColor('#808080')
            .textAlign(TextAlign.Center)
            .lineHeight(20)
            .margin({ bottom: 24 })
          Text('去登录')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .height(44)
            .padding({ left: 32, right: 32 })
            .backgroundColor('#3390EC')
            .borderRadius(22)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/Index' });
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 32, right: 32 })
      } else {
        List({ space: 10 }) {
          ForEach(this.scores, (it: EasCourseScoreItem) => {
            ListItem() {
              Column() {
                // ── Top row: course name + score ──
                Row() {
                  Text(it.courseName)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#1A1A1A')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  Text(it.displayScore())
                    .fontSize(22)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(ScorePage.scoreColor(it))
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                // ── Detail rows ──
                Row({ space: 6 }) {
                  Text(it.courseCode)
                    .fontSize(12)
                    .fontColor('#808080')
                  Text('·')
                    .fontSize(12)
                    .fontColor('#B0B4BA')
                  Text(it.courseProperty.length > 0 ? it.courseProperty : '—')
                    .fontSize(12)
                    .fontColor('#808080')
                  Text('·')
                    .fontSize(12)
                    .fontColor('#B0B4BA')
                  Text(it.courseCategory.length > 0 ? it.courseCategory : '—')
                    .fontSize(12)
                    .fontColor('#808080')
                }
                .width('100%')
                .margin({ top: 6 })

                Row({ space: 4 }) {
                  Text('学分')
                    .fontSize(12)
                    .fontColor('#B0B4BA')
                  Text(ScorePage.num(it.credits))
                    .fontSize(12)
                    .fontColor('#808080')
                    .fontWeight(FontWeight.Medium)
                  Text('·')
                    .fontSize(12)
                    .fontColor('#B0B4BA')
                  Text('学时')
                    .fontSize(12)
                    .fontColor('#B0B4BA')
                  Text(it.hours.toString())
                    .fontSize(12)
                    .fontColor('#808080')
                    .fontWeight(FontWeight.Medium)
                  if (it.assessMethod.length > 0) {
                    Text('·')
                      .fontSize(12)
                      .fontColor('#B0B4BA')
                    Text(it.assessMethod)
                      .fontSize(12)
                      .fontColor('#808080')
                  }
                  Text('·')
                    .fontSize(12)
                    .fontColor('#B0B4BA')
                  Text(it.termName)
                    .fontSize(12)
                    .fontColor('#808080')
                }
                .width('100%')
                .margin({ top: 4 })

                // ── School name ──
                if (it.schoolName.length > 0) {
                  Text(it.schoolName)
                    .fontSize(11)
                    .fontColor('#B0B4BA')
                    .width('100%')
                    .margin({ top: 6 })
                }
              }
              .width('100%')
              .padding(14)
              .backgroundColor('#FFFFFF')
              .borderRadius(12)
              .shadow({ radius: 8, color: '#14000000', offsetY: 2 })
            }
          }, (it: EasCourseScoreItem) => it.courseCode + it.termName)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 14, right: 14, top: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F7FA')
  }

  static num(v: number): string {
    const s: string = v.toString();
    if (s.indexOf('.') < 0) {
      return s + '.0';
    }
    return s;
  }

  static scoreColor(it: EasCourseScoreItem): string {
    if (it.finalScores >= 90) {
      return '#2E7D32';
    }
    if (it.finalScores >= 80) {
      return '#3390EC';
    }
    if (it.finalScores >= 60) {
      return '#808080';
    }
    if (it.finalScoresText.length > 0 && it.finalScores < 0) {
      return '#3390EC'; // 等级制文本（优/良/通过…）
    }
    return '#D93025';
  }
}
