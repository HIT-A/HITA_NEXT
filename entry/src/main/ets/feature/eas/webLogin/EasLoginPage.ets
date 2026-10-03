/**
 * EasLoginPage.ets — ArkWeb 网页登录页（对应 Android WebViewLoginActivity / WebViewLoginScreen）。
 *
 * UI 布局对齐安卓：
 *  - 顶部标题栏：左侧返回应用，右侧网页回退和刷新，各自占用独立布局空间。
 *  - 线性进度条：3vp 高度，仅在加载中展示。
 *  - Web 组件：直接绑定登录 URL，并在控制器附着后完成登录状态初始化。
 *  - MFA 覆盖层：仅在触发二次认证时浮层提示。
 */
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { EasSession } from '../EasSession';
import { EasSessionStore } from '../EasSessionStore';
import { EasWebLoginController } from './EasWebLoginController';
import { EasMfaOverlayState } from './EasWebMfaBridge';
import { easWebLoginConfigFor, EasCampusConfig } from './EasWebLoginConfig';
import { HitaColors } from '../../../common/theme/HitaColors';
import { HeaderBackButton } from '../../../common/components/HeaderBackButton';

const TAG: string = 'HitaLoginPage';
const DOMAIN: number = 0x0000;

@Component
export struct EasLoginPage {
  @Prop campusCode: string = 'SHENZHEN';
  @Prop studentType: string = '1';
  onCancel: () => void = () => {};
  onLoggedIn: (session: EasSession) => void = () => {};

  private webController: webview.WebviewController = new webview.WebviewController();
  private loginController: EasWebLoginController = new EasWebLoginController();
  private attachStarted: boolean = false;

  @State progressValue: number = 0;
  @State errorText: string = '';
  @State initialUrl: string = '';
  @State campusDisplayName: string = '统一认证登录';
  @State webReady: boolean = false;
  @State canGoBack: boolean = false;

  // —— 原生 MFA 覆盖层 ——
  @State mfaState: EasMfaOverlayState = new EasMfaOverlayState();
  @State mfaInput: string = '';
  @State mfaBusy: boolean = false;

  aboutToAppear(): void {
    // 必须在 Web 组件开始导航前开启 Cookie。安卓版在 loadUrl 前完成同样的初始化，
    // 否则 WebVPN/CAS 的跨站 Set-Cookie 可能被 ArkWeb 丢弃。
    EasWebLoginController.configureWebCookies();
    const campus = EasWebLoginController.campusOfCode(this.campusCode);
    const cfg: EasCampusConfig = easWebLoginConfigFor(campus, this.studentType);
    this.initialUrl = cfg.loginUrl;
    this.campusDisplayName = cfg.displayName;

    hilog.info(DOMAIN, TAG, 'EasLoginPage aboutToAppear: campus=%{public}s, initialUrl=%{public}s',
      this.campusCode, this.initialUrl);

    const ctrl: EasWebLoginController = this.loginController;
    ctrl.onProgress = (p: number) => {
      this.progressValue = p;
    };
    ctrl.onMfaStateChanged = (state: EasMfaOverlayState) => {
      this.mfaState = state;
      this.mfaInput = '';
    };
    ctrl.onError = (message: string) => {
      this.errorText = message;
    };
    ctrl.onFinished = (session: EasSession) => {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      EasSessionStore.getInstance().init(ctx).then(() => {
        return EasSessionStore.getInstance().load(session.campus);
      }).then((oldSession: EasSession | undefined) => {
        if (oldSession !== undefined && oldSession.sessionGeneration > 0) {
          session.sessionGeneration = oldSession.sessionGeneration + 1;
        }
        return EasSessionStore.getInstance().save(session);
      }).then(() => {
        this.onLoggedIn(session);
      }).catch(() => {
        this.onLoggedIn(session);
      });
    };
  }

  aboutToDisappear(): void {
    this.loginController.stop();
  }

  private updateWebNavigation(): void {
    try {
      this.canGoBack = this.webController.accessBackward();
    } catch (e) {
      this.canGoBack = false;
    }
  }

  private navigateWebBack(): void {
    try {
      if (this.webController.accessBackward()) {
        this.webController.backward();
      }
    } catch (e) {}
    this.updateWebNavigation();
  }

  private cancelLogin(): void {
    this.loginController.stop();
    this.onCancel();
  }

  build() {
    Column() {
      // Android WebViewLoginActivity uses a compact white app bar with a thin
      // brand accent, leaving the authentication page itself visually calm.
      Row({ space: 8 }) {
        HeaderBackButton({
          accessibilityLabel: '返回应用',
          onBack: () => this.cancelLogin()
        });

        Column() {
          Text('统一认证登录')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(HitaColors.onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.campusDisplayName)
            .fontSize(12)
            .fontColor(HitaColors.primary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(18)
            .fontColor([HitaColors.onSurface]);
        }
        .width(36)
        .height(44)
        .padding(0)
        .flexShrink(0)
        .backgroundColor(Color.Transparent)
        .enabled(this.canGoBack)
        .opacity(this.canGoBack ? 1 : 0.35)
        .accessibilityText('返回上一网页')
        .onClick(() => {
          this.navigateWebBack();
        });

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.repeat_1'))
            .fontSize(20)
            .fontColor([HitaColors.primary]);
        }
        .width(40)
        .height(44)
        .padding(0)
        .flexShrink(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('刷新认证网页')
        .onClick(() => {
          try {
            this.webReady = false;
            this.progressValue = 0;
            this.webController.refresh();
          } catch (e) {}
        });

      }
      .width('100%')
      .height(62)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')
      .border({ width: { bottom: 1 }, color: HitaColors.divider })
      .alignItems(VerticalAlign.Center)

      // ═══════════════ 线性进度条（对齐安卓 LinearProgressIndicator） ═══════════════
      Progress({ value: this.progressValue, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(3)
        .color(HitaColors.primary)
        .backgroundColor('#E8F1FB')
        .visibility(this.webReady ? Visibility.None : Visibility.Visible)

      // 错误提示条
      if (this.errorText.length > 0) {
        Row() {
          Text(this.errorText)
            .fontSize(12)
            .fontColor('#B91C1C')
            .layoutWeight(1)
          Text('✕')
            .fontSize(12)
            .fontColor('#B91C1C')
            .onClick(() => {
              this.errorText = '';
            })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 9, bottom: 9 })
        .backgroundColor('#FFF1F0')
        .border({ width: { bottom: 1 }, color: '#FFD6D2' })
      }

      // ═══════════════ Web 容器（占满全屏剩余空间） ═══════════════
      Stack({ alignContent: Alignment.Center }) {
        if (this.initialUrl.length > 0) {
          Web({ src: this.initialUrl, controller: this.webController })
            .domStorageAccess(true)
            .javaScriptAccess(true)
            .databaseAccess(true)
            .fileAccess(true)
            .imageAccess(true)
            .onlineImageAccess(true)
            .mixedMode(MixedMode.All)
            // 安卓版启用了多窗口；CAS/WebVPN 部分页面会通过新窗口继续认证。
            .multiWindowAccess(true)
            .allowWindowOpenMethod(true)
            .onWindowNew((event) => {
              if (event && event.targetUrl && event.targetUrl.length > 0) {
                try {
                  this.webController.loadUrl(event.targetUrl);
                } catch (e) {}
              }
            })
            .onControllerAttached(() => {
              if (this.attachStarted) {
                return;
              }
              this.attachStarted = true;
              hilog.info(DOMAIN, TAG, 'Web controller attached, starting EAS login: %{public}s', this.initialUrl);
              this.loginController.attachWeb(this.webController);
              this.loginController.start(this.campusCode, this.studentType);
            })
            .onPageBegin((event) => {
              const u: string = event !== undefined && event !== null ? event.url : '';
              this.progressValue = 0;
              this.webReady = false;
              this.updateWebNavigation();
              this.loginController.notifyPageBegin(u);
            })
            .onPageEnd((event) => {
              const u: string = event !== undefined && event !== null ? event.url : '';
              this.webReady = true;
              this.updateWebNavigation();
              this.loginController.notifyPageEnd(u);
            })
            .onProgressChange((event) => {
              const p: number = event !== undefined && event !== null ? event.newProgress : 0;
              this.progressValue = p;
              this.loginController.notifyProgress(p);
            })
            .onErrorReceive((event) => {
              if (event !== undefined && event !== null && event.error !== undefined && event.error !== null) {
                let errStr: string = '';
                try {
                  errStr = event.error.getErrorInfo ? event.error.getErrorInfo() : String(event.error);
                } catch (e) {
                  errStr = String(event.error);
                }
                this.loginController.notifyLoadError(errStr);
              }
            })
            .onConsole((event) => {
              if (event !== undefined && event !== null && event.message !== undefined && event.message !== null) {
                hilog.info(DOMAIN, 'HitaWebConsole', '[%{public}s] %{public}s',
                  event.message.getSourceId ? event.message.getSourceId() : '',
                  event.message.getMessage ? event.message.getMessage() : '');
              }
              return false;
            })
            .width('100%')
            .height('100%')
        }

        if (!this.webReady && !this.mfaState.visible) {
          Column() {
            Image($r('app.media.app_icon'))
              .width(54)
              .height(54)
              .objectFit(ImageFit.Contain)
              .borderRadius(15)
              .backgroundColor('#FFFFFF')
              .shadow({ radius: 12, color: '#14000000', offsetY: 4 });
            LoadingProgress()
              .width(28)
              .height(28)
              .color(HitaColors.primary)
              .margin({ top: 18, bottom: 12 });
            Text('正在打开统一认证页面')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(HitaColors.onSurface);
            Text('请稍候，登录过程将在校区教务页面内完成')
              .fontSize(12)
              .fontColor(HitaColors.onSurfaceVariant)
              .margin({ top: 7 });
          }
          .padding({ left: 24, right: 24, top: 24, bottom: 24 })
          .borderRadius(18)
          .backgroundColor('#FFFFFF')
          .shadow({ radius: 18, color: '#18000000', offsetY: 6 });
        }

        // ═══════════════ 原生 MFA 覆盖层 ═══════════════
        if (this.mfaState.visible) {
          Column() {
            Column() {
              Text(this.mfaState.promptTitle.length > 0 ? this.mfaState.promptTitle : '二次验证')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(HitaColors.onSurface)
                .margin({ bottom: 8 })

              if (this.mfaState.promptText.length > 0) {
                Text(this.mfaState.promptText)
                  .fontSize(14)
                  .fontColor(HitaColors.onSurfaceVariant)
                  .margin({ bottom: 16 })
              }

              if (this.mfaState.hasVisibleInput) {
                TextInput({
                  placeholder: this.mfaState.inputPlaceholder.length > 0 ?
                    this.mfaState.inputPlaceholder : '请输入验证码',
                  text: this.mfaInput
                })
                  .type(InputType.Normal)
                  .fontSize(16)
                  .height(44)
                  .backgroundColor('#F3F4F6')
                  .borderRadius(8)
                  .padding({ left: 12, right: 12 })
                  .onChange((value: string) => {
                    this.mfaInput = value;
                  })
                  .margin({ bottom: 16 })
              }

              Row({ space: 10 }) {
                if (this.mfaState.canSendCode) {
                  Button('发送验证码')
                    .fontSize(13)
                    .height(36)
                    .borderRadius(18)
                    .backgroundColor('#FFFFFF')
                    .fontColor(HitaColors.primary)
                    .border({ width: 1, color: HitaColors.primary })
                    .onClick(() => {
                      this.mfaBusy = true;
                      this.loginController.sendMfaCode().finally(() => {
                        this.mfaBusy = false;
                      });
                    })
                }
                if (this.mfaState.verifyMethodType.length > 0 || this.mfaState.switchMethodJs.length > 0) {
                  Button('切换方式')
                    .fontSize(13)
                    .height(36)
                    .borderRadius(18)
                    .backgroundColor('#FFFFFF')
                    .fontColor(HitaColors.primary)
                    .border({ width: 1, color: HitaColors.primary })
                    .onClick(() => {
                      this.loginController.switchMfaMethod();
                    })
                }
              }
              .margin({ bottom: 16 })
              .justifyContent(FlexAlign.Center)

              Button(this.mfaBusy ? '提交中…' : '提交')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .width('100%')
                .height(44)
                .borderRadius(22)
                .backgroundColor(HitaColors.primary)
                .fontColor(HitaColors.onPrimary)
                .enabled(!this.mfaBusy)
                .onClick(() => {
                  if (this.mfaInput.trim().length === 0) {
                    return;
                  }
                  this.mfaBusy = true;
                  this.loginController.submitMfaInput(this.mfaInput.trim()).finally(() => {
                    this.mfaBusy = false;
                  });
                })
            }
            .width('88%')
            .padding({ left: 22, right: 22, top: 22, bottom: 22 })
            .borderRadius(20)
            .backgroundColor('#FFFFFF')
            .shadow({ radius: 22, color: 'rgba(0,0,0,0.18)', offsetY: 8 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('rgba(15,23,42,0.46)')
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
