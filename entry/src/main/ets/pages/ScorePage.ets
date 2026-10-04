/**
 * ScorePage.ets — 成绩查询。
 *
 * 需要教务会话：无会话 → 空态引导去登录；有会话 → 拉取学期成绩并渲染。
 */
import { common } from '@kit.AbilityKit';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { HeaderFadeMask } from '../common/components/HeaderFadeMask';
import { HeaderFade } from '../common/theme/HeaderFade';
import { STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { EasCampus, EasSession } from '../feature/eas/EasSession';
import { EasSessionStore } from '../feature/eas/EasSessionStore';
import { EasDataProvider } from '../feature/eas/EasDataProvider';
import { EasUserMessages } from '../feature/eas/EasUserMessages';
import { EasCourseScoreItem, EasTermItem } from '../feature/eas/model/EasModels';
import { EasApiClient } from '../feature/eas/EasApiClient';

const HEADER_HEIGHT: number = 60;
const PAGE_BG: string = '#F6F7FA';
const PAGE_BG_RGB: string = '246,247,250';

@Entry
@Component
struct ScorePage {
  @State modeText: string = '';
  @State msg: string = '';
  @State scores: EasCourseScoreItem[] = [];
  @State loading: boolean = false;
  @State hasSession: boolean = false;
  @State fadeOpacity: number = 0;
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  private session: EasSession | undefined = undefined;
  private pageScroller: Scroller = new Scroller();

  async aboutToAppear(): Promise<void> {
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
      this.hasSession = true;
      this.modeText = '当前会话：' + ScorePage.campusText(this.session.campus);
    } else {
      this.modeText = '未登录教务';
    }
  }

  /** 拉取当前学期成绩：需要网页登录会话。 */
  async queryReal(): Promise<void> {
    if (this.session === undefined) {
      this.msg = '请先登录教务';
      return;
    }
    this.loading = true;
    this.msg = '正在查询…';
    try {
      const provider: EasDataProvider = new EasDataProvider(new EasApiClient());
      const terms: EasTermItem[] = await provider.getAllTerms(this.session);
      if (terms.length === 0) {
        this.msg = '未获取到学期信息，请稍后重试';
        return;
      }
      const term: EasTermItem = terms[0];
      const result = await provider.getPersonalScores(this.session, term);
      if (result.ok) {
        this.scores = result.items;
        this.modeText = ScorePage.campusText(this.session.campus) + ' · ' + term.name;
        this.msg = result.items.length > 0 ? '共 ' + result.items.length.toString() + ' 条成绩' : '本学期暂无成绩';
      } else {
        this.msg = EasUserMessages.fromError(result.msg, '成绩查询失败，请稍后重试');
      }
    } catch (e) {
      this.msg = EasUserMessages.fromError(e instanceof Error ? e.message : String(e),
        '成绩查询失败，请稍后重试');
    } finally {
      this.loading = false;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
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
        .height('100%')
        .padding({ top: HEADER_HEIGHT })
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
          Text(this.hasSession ? '点击右上角“查询”获取成绩' : '登录教务后即可查询成绩')
            .fontSize(13)
            .fontColor('#808080')
            .textAlign(TextAlign.Center)
            .lineHeight(20)
            .margin({ bottom: 24 })
          if (!this.hasSession) {
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
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/Home',
                  params: { 'openSession': '1' }
                });
              })
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 32, right: 32, top: HEADER_HEIGHT })
      } else {
        List({ space: 10, scroller: this.pageScroller }) {
          ListItem() {
            Column()
              .width('100%')
              .height(HEADER_HEIGHT)
          }
          ListItem() {
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
            .padding({ left: 2, right: 2, top: 2, bottom: 6 })
          }
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
        .height('100%')
        .padding({ left: 14, right: 14, bottom: 16 })
        .scrollBar(BarState.Off)
        .onDidScroll(() => {
          this.fadeOpacity = HeaderFade.opacity(this.pageScroller.currentOffset().yOffset);
        })
      }

      HeaderFadeMask({
        maskOpacity: this.fadeOpacity,
        rgb: PAGE_BG_RGB,
        headerHeight: HEADER_HEIGHT
      })

      Row() {
        HeaderBackButton({
          onBack: () => this.getUIContext().getRouter().back()
        })
          .margin({ right: 12 })
        Text('成绩查询')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text('查询')
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
      }
      .width('100%')
      .height(HEADER_HEIGHT)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarInset })
    .backgroundColor(PAGE_BG)
  }

  static campusText(c: EasCampus): string {
    if (c === EasCampus.SHENZHEN) {
      return '深圳校区';
    }
    if (c === EasCampus.BENBU) {
      return '本部';
    }
    return '威海校区';
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
