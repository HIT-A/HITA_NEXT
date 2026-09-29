/**
 * Index.ets — 首页：EAS 登录与离线功能开发入口（P0 阶段开发页，内容较多故可滚动）。
 *
 * 当前入口：登录子系统、本地数据与深圳课表/成绩链路均已就绪；Home 使用今日/课表/我的三 Tab。
 */
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { EasCampus, EasSession } from '../feature/eas/EasSession';
import { EasSessionStore } from '../feature/eas/EasSessionStore';
import { EasDataProvider } from '../feature/eas/EasDataProvider';
import { EasLoginPage } from '../feature/eas/webLogin/EasLoginPage';
import { TimetableLocalDemo } from '../feature/timetable/data/TimetableLocalDemo';

interface CampusOption {
  code: string;
  label: string;
}

@Entry
@Component
struct Index {
  @State campusOptions: CampusOption[] = [
    { code: 'SHENZHEN', label: '深圳' },
    { code: 'BENBU', label: '本部' },
    { code: 'WEIHAI', label: '威海' }
  ];
  @State selectedCampus: string = 'SHENZHEN';
  @State selectedType: string = '1'; // 1 本科 2 研究生（仅本部区分）
  @State showLogin: boolean = false;
  @State sessionSummary: string = '（无会话）';
  @State hasSession: boolean = false;
  @State parserLog: string = '（未运行）';
  @State dbLog: string = '（未运行）';
  @State hasLocalDemo: boolean = false;

  async aboutToAppear(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    await EasSessionStore.getInstance().init(ctx);
    await this.refreshSummary();
    this.parserLog = EasDataProvider.runParserSelfCheck();
  }

  campusOf(code: string): EasCampus {
    if (code === 'BENBU') {
      return EasCampus.BENBU;
    }
    if (code === 'WEIHAI') {
      return EasCampus.WEIHAI;
    }
    return EasCampus.SHENZHEN;
  }

  async refreshSummary(): Promise<void> {
    const session: EasSession | undefined = await EasSessionStore.getInstance().load(this.campusOf(this.selectedCampus));
    if (session !== undefined && session.isLogin()) {
      this.hasSession = true;
      this.sessionSummary = session.campus.toString() +
        ' | cookies=' + session.webCookies.size.toString() +
        ' | gen=' + session.sessionGeneration.toString() +
        (session.webBaseUrl.length > 0 ? '\nbase=' + session.webBaseUrl : '') +
        (session.name.length > 0 ? '\n' + session.name : '');
    } else {
      this.hasSession = false;
      this.sessionSummary = '（无会话）';
    }
  }

  async onSessionUpdated(session: EasSession): Promise<void> {
    this.showLogin = false;
    await this.refreshSummary();
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor('#8A8F99')
      .letterSpacing(1)
      .alignSelf(ItemAlign.Start)
      .margin({ left: 20, top: 16, bottom: 6 })
  }

  build() {
    Stack() {
      Scroll() {
        Column() {
          Text('HITA · 鸿蒙 NEXT 移植')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .margin({ top: 24, bottom: 2 })
          Text('功能 × 新版登录整合实现蓝本 v1.0')
            .fontSize(12)
            .fontColor('#888888')
            .margin({ bottom: 10 })

          this.sectionTitle('① EAS 登录与会话')

          Row({ space: 8 }) {
            ForEach(this.campusOptions, (item: CampusOption) => {
              Button(item.label)
                .fontSize(15)
                .backgroundColor(this.selectedCampus === item.code ? '#2B6CB0' : '#EDF1F7')
                .fontColor(this.selectedCampus === item.code ? '#FFFFFF' : '#333333')
                .onClick(() => {
                  this.selectedCampus = item.code;
                  this.refreshSummary();
                })
            }, (item: CampusOption) => item.code)
          }
          .width('90%')

          Row({ space: 8 }) {
            Button('本科')
              .fontSize(15)
              .backgroundColor(this.selectedType === '1' ? '#2B6CB0' : '#EDF1F7')
              .fontColor(this.selectedType === '1' ? '#FFFFFF' : '#333333')
              .onClick(() => {
                this.selectedType = '1';
              })
            Button('研究生')
              .fontSize(15)
              .backgroundColor(this.selectedType === '2' ? '#2B6CB0' : '#EDF1F7')
              .fontColor(this.selectedType === '2' ? '#FFFFFF' : '#333333')
              .onClick(() => {
                this.selectedType = '2';
              })
          }
          .width('90%')
          .margin({ top: 10 })

          Button('网页登录' + (this.hasSession ? '（重登）' : ''))
            .width('90%')
            .height(44)
            .margin({ top: 16 })
            .backgroundColor('#2B6CB0')
            .onClick(() => {
              this.showLogin = true;
            })

          if (this.hasSession) {
            Button('清除当前校区会话')
              .width('90%')
              .height(38)
              .margin({ top: 8 })
              .backgroundColor('#FFFFFF')
              .fontColor('#D93025')
              .border({ width: 1, color: '#D93025' })
              .onClick(() => {
                EasSessionStore.getInstance().clear(this.campusOf(this.selectedCampus)).then(() => {
                  this.refreshSummary();
                });
              })
          }

          Column() {
            Text('当前会话')
              .fontSize(12)
              .fontColor('#999999')
            Text(this.sessionSummary)
              .fontSize(13)
              .fontColor(this.hasSession ? '#2E7D32' : '#999999')
              .textAlign(TextAlign.Start)
              .width('100%')
              .margin({ top: 4 })
          }
          .width('90%')
          .padding(12)
          .margin({ top: 12 })
          .backgroundColor('#F5F6F8')
          .borderRadius(10)
          .alignItems(HorizontalAlign.Start)

          this.sectionTitle('② 离线功能预览')

          Button('今日时间线（含演示数据）')
            .width('90%')
            .height(42)
            .margin({ top: 4 })
            .backgroundColor('#2E7D32')
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/TimeLinePage' });
            })

          Button('课表周视图预览')
            .width('90%')
            .height(42)
            .margin({ top: 8 })
            .backgroundColor('#6A4FA3')
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/TimetablePreview' });
            })

          Button('成绩查询页（会话/样例）')
            .width('90%')
            .height(42)
            .margin({ top: 8 })
            .backgroundColor('#B3261E')
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/ScorePage' });
            })

          Button('我的（会话管理）')
            .width('90%')
            .height(42)
            .margin({ top: 8 })
            .backgroundColor('#455A64')
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/ProfilePage' });
            })

          Button('科目管理')
            .width('90%')
            .height(42)
            .margin({ top: 8 })
            .backgroundColor('#FFFFFF')
            .fontColor('#455A64')
            .border({ width: 1, color: '#455A64' })
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/SubjectsPage' });
            })

          Button('考试查询页')
            .width('90%')
            .height(42)
            .margin({ top: 8 })
            .backgroundColor('#FFFFFF')
            .fontColor('#B3261E')
            .border({ width: 1, color: '#B3261E' })
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/ExamPage' });
            })

          Button('本地搜索（教师/地点）')
            .width('90%')
            .height(42)
            .margin({ top: 8 })
            .backgroundColor('#FFFFFF')
            .fontColor('#00696D')
            .border({ width: 1, color: '#00696D' })
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/SearchPage' });
            })

          this.sectionTitle('③ 本地演示与自检')

          Button('生成本地演示数据（课表/今日事件，RDB）')
            .width('90%')
            .height(40)
            .backgroundColor('#FFFFFF')
            .fontColor('#6A4FA3')
            .border({ width: 1, color: '#6A4FA3' })
            .onClick(() => {
              const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
              TimetableLocalDemo.runSelfCheck(ctx).then((summary: string) => {
                this.dbLog = summary;
                this.hasLocalDemo = true;
              }).catch((e: Error) => {
                this.dbLog = '自检失败：' + e.message;
              });
            })

          Button('离线解析自检（深圳成绩 + 课表 JSON）')
            .width('90%')
            .height(40)
            .margin({ top: 8 })
            .backgroundColor('#FFFFFF')
            .fontColor('#2E7D32')
            .border({ width: 1, color: '#2E7D32' })
            .onClick(() => {
              this.parserLog = EasDataProvider.runParserSelfCheck();
            })

          Column() {
            Text('本地课表 RDB 自检输出')
              .fontSize(12)
              .fontColor('#999999')
            Text(this.dbLog)
              .fontSize(12)
              .fontColor('#333333')
              .textAlign(TextAlign.Start)
              .width('100%')
              .margin({ top: 4 })
          }
          .width('90%')
          .padding(12)
          .margin({ top: 12 })
          .backgroundColor('#F5F0FA')
          .borderRadius(10)
          .alignItems(HorizontalAlign.Start)

          Column() {
            Text('解析自检输出')
              .fontSize(12)
              .fontColor('#999999')
            Text(this.parserLog)
              .fontSize(12)
              .fontColor('#333333')
              .textAlign(TextAlign.Start)
              .width('100%')
              .margin({ top: 4 })
          }
          .width('90%')
          .padding(12)
          .margin({ top: 10 })
          .backgroundColor('#F0F7F0')
          .borderRadius(10)
          .alignItems(HorizontalAlign.Start)

          Text('说明：网页登录需要真机访问校园门户；课表、时间线和事件支持本地演示。' +
            ' 深圳登录会话可请求真实课表与成绩，首次联调请检查 Cookie 和校园网络。')
            .fontSize(11)
            .fontColor('#B0B4BA')
            .width('90%')
            .margin({ top: 20, bottom: 60 })
            .textAlign(TextAlign.Start)
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .backgroundColor('#FFFFFF')

      if (this.showLogin) {
        Stack() {
          EasLoginPage({
            campusCode: this.selectedCampus,
            studentType: this.selectedType,
            onCancel: () => {
              this.showLogin = false;
            },
            onLoggedIn: (session: EasSession) => {
              this.onSessionUpdated(session);
            }
          })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }
}
