/** HITA NEXT 登录入口，视觉结构对齐 Android WelcomeActivity。 */
import { common } from '@kit.AbilityKit';
import { EasLoginPage } from '../feature/eas/webLogin/EasLoginPage';
import { EasSession } from '../feature/eas/EasSession';
import { EasSessionStore } from '../feature/eas/EasSessionStore';
import { EasCampus } from '../feature/eas/EasSession';
import { HitaColors } from '../common/theme/HitaColors';

interface CampusItem {
  code: string;
  label: string;
  description: string;
}

interface TypeItem {
  code: string;
  label: string;
}

@Entry
@Component
struct WelcomePage {
  @State selectedCampus: string = 'SHENZHEN';
  @State selectedType: string = '1';
  @State showLogin: boolean = false;

  private readonly campuses: CampusItem[] = [
    { code: 'SHENZHEN', label: '深圳', description: '深圳校区教务' },
    { code: 'BENBU', label: '本部', description: '本部教务' },
    { code: 'WEIHAI', label: '威海', description: '威海教务' }
  ];

  private readonly types: TypeItem[] = [
    { code: '1', label: '本科' },
    { code: '2', label: '研究生' }
  ];

  async aboutToAppear(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    await EasSessionStore.getInstance().init(ctx);
    const order: EasCampus[] = [EasCampus.SHENZHEN, EasCampus.BENBU, EasCampus.WEIHAI];
    for (let i: number = 0; i < order.length; i++) {
      const session: EasSession | undefined = await EasSessionStore.getInstance().load(order[i]);
      if (session !== undefined && session.isLogin()) {
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/Home' });
        return;
      }
    }
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Stack() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(22)
              .fontColor([HitaColors.onSurface]);
          }
          .width(42)
          .height(42)
          .borderRadius(21)
          .alignContent(Alignment.Center)
          .backgroundColor('#FFFFFF')
          .onClick(() => {
            try {
              this.getUIContext().getRouter().back();
            } catch (e) {
              // Welcome is also a launch destination; there may be no history.
            }
          });
          Blank().layoutWeight(1);
          Text('登录入口')
            .fontSize(14)
            .fontColor(HitaColors.onSurfaceVariant);
        }
        .width('100%')
        .padding({ left: 18, right: 20, top: 12, bottom: 4 });

        Scroll() {
          Column() {
            Column() {
              Image($r('app.media.app_icon'))
                .width(112)
                .height(112)
                .objectFit(ImageFit.Contain)
                .borderRadius(28)
                .backgroundColor('#FFFFFF')
                .shadow({ radius: 16, color: '#16000000', offsetY: 8 });
              Text('HITA')
                .fontSize(34)
                .fontWeight(FontWeight.Bold)
                .fontColor(HitaColors.onSurface)
                .margin({ top: 18 });
              Text('哈尔滨工业大学校园助手')
                .fontSize(15)
                .fontColor(HitaColors.onSurfaceVariant)
                .margin({ top: 5 });
              Row() {
                SymbolGlyph($r('sys.symbol.checkmark_circle'))
                  .fontSize(14)
                  .fontColor([HitaColors.primary]);
                Text('HarmonyOS NEXT · 与 Android 版保持一致的数据逻辑')
                  .fontSize(11)
                  .fontColor(HitaColors.primary)
                  .margin({ left: 5 });
              }
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(14)
              .backgroundColor(HitaColors.primaryContainer)
              .margin({ top: 14 });
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 24, bottom: 28 });

            Column() {
              Row() {
                Column() {
                  Text('欢迎回来')
                    .fontSize(22)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(HitaColors.onSurface);
                  Text('使用统一身份认证连接你的教务数据')
                    .fontSize(13)
                    .fontColor(HitaColors.onSurfaceVariant)
                    .margin({ top: 6 });
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start);
                Text('HITA')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(HitaColors.primary)
                  .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                  .borderRadius(10)
                  .backgroundColor(HitaColors.primaryContainer);
              }
              .width('100%');

              Text('选择校区')
                .fontSize(12)
                .fontColor(HitaColors.onSurfaceVariant)
                .alignSelf(ItemAlign.Start)
                .margin({ top: 24, bottom: 10 });
              Row({ space: 8 }) {
                ForEach(this.campuses, (item: CampusItem) => {
                  Column() {
                    Text(item.label)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.selectedCampus === item.code ? HitaColors.primary : HitaColors.onSurface);
                    Text(item.description)
                      .fontSize(10)
                      .fontColor(this.selectedCampus === item.code ? HitaColors.primary : HitaColors.muted)
                      .margin({ top: 4 });
                  }
                  .layoutWeight(1)
                  .height(68)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .borderRadius(12)
                  .backgroundColor(this.selectedCampus === item.code ? HitaColors.primaryContainer : '#F4F5F7')
                  .border({
                    width: this.selectedCampus === item.code ? 1.5 : 1,
                    color: this.selectedCampus === item.code ? HitaColors.primary : '#EAECF0'
                  })
                  .onClick(() => {
                    this.selectedCampus = item.code;
                  });
                }, (item: CampusItem) => item.code)
              }
              .width('100%');

              Text('培养层次')
                .fontSize(12)
                .fontColor(HitaColors.onSurfaceVariant)
                .alignSelf(ItemAlign.Start)
                .margin({ top: 18, bottom: 10 });
              Row() {
                ForEach(this.types, (item: TypeItem) => {
                  Text(item.label)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.selectedType === item.code ? HitaColors.onPrimary : HitaColors.onSurfaceVariant)
                    .textAlign(TextAlign.Center)
                    .layoutWeight(1)
                    .height(40)
                    .padding({ top: 10, bottom: 10 })
                    .borderRadius(20)
                    .backgroundColor(this.selectedType === item.code ? HitaColors.primary : 'transparent')
                    .onClick(() => {
                      this.selectedType = item.code;
                    });
                }, (item: TypeItem) => item.code)
              }
              .width('100%')
              .padding(3)
              .borderRadius(23)
              .backgroundColor('#F1F3F5');

              Button({ type: ButtonType.Capsule }) {
                Row() {
                  Text('使用统一身份认证登录')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(HitaColors.onPrimary);
                  SymbolGlyph($r('sys.symbol.arrow_right'))
                    .fontSize(17)
                    .fontColor([HitaColors.onPrimary])
                    .margin({ left: 8 });
                }
                .justifyContent(FlexAlign.Center)
              }
              .width('100%')
              .height(50)
              .backgroundColor(HitaColors.primary)
              .margin({ top: 22 })
              .shadow({ radius: 10, color: '#263390EC', offsetY: 5 })
              .onClick(() => {
                this.showLogin = true;
              });

              Row() {
                SymbolGlyph($r('sys.symbol.lock_shield'))
                  .fontSize(15)
                  .fontColor([HitaColors.muted]);
                Text('认证在校区教务页面内完成，HITA 不保存认证密码')
                  .fontSize(11)
                  .fontColor(HitaColors.muted)
                  .margin({ left: 5 });
              }
              .margin({ top: 14 })
              .alignSelf(ItemAlign.Center);
            }
            .width('100%')
            .padding(20)
            .borderRadius(18)
            .backgroundColor('#FFFFFF')
            .shadow({ radius: 18, color: '#12000000', offsetY: 6 });

            Text('版本 0.1.0 · HITA NEXT')
              .fontSize(11)
              .fontColor(HitaColors.muted)
              .margin({ top: 20, bottom: 26 });
          }
          .width('100%')
          .padding({ left: 18, right: 18 });
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off);
      }
      .width('100%')
      .height('100%')
      .backgroundColor(HitaColors.surface);

      if (this.showLogin) {
        EasLoginPage({
          campusCode: this.selectedCampus,
          studentType: this.selectedType,
          onCancel: () => {
            this.showLogin = false;
          },
          onLoggedIn: (session: EasSession) => {
            this.showLogin = false;
            this.getUIContext().getRouter().replaceUrl({ url: 'pages/Home' });
          }
        })
          .width('100%')
          .height('100%');
      }
    }
    .width('100%')
    .height('100%');
  }
}
