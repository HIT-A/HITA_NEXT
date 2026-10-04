/**
 * AssistantTab.ets — 主页「助手」栏：课表问答 + 可选云端大模型。
 * 顶部抬头与功能中心相同：Scroll 占位 + 渐隐遮罩 + 覆盖标题。
 */
import { common } from '@kit.AbilityKit';
import { HeaderFadeMask } from '../../common/components/HeaderFadeMask';
import { HeaderFade } from '../../common/theme/HeaderFade';
import { AssistantMessage, AssistantRole, AssistantService } from './AssistantService';
import { AssistantProvider, AssistantSettings, AssistantSettingsStore } from './AssistantSettingsStore';
import { KEYBOARD_INSET_FALLBACK, NAV_BAR_INSET_FALLBACK, STATUS_BAR_INSET_FALLBACK } from '../../common/theme/StatusBarInset';

const COLOR_PRIMARY: string = '#2E86E8';
const COLOR_CARD: string = '#FFFFFF';
const COLOR_TEXT_PRIMARY: string = '#14213D';
const COLOR_TEXT_SECONDARY: string = '#4E5C72';
const COLOR_TEXT_HINT: string = '#5A6880';
const COLOR_NAV_ACTIVE: string = '#E3EEFC';
const SURFACE_RGB: string = '244,247,252';
const DOCK_CLEARANCE: number = 64;
const HEADER_BODY: number = 56;

class AssistantChatHistory {
  static messages: AssistantMessage[] = [AssistantService.welcome()];
}

@Component
export struct AssistantTab {
  @State messages: AssistantMessage[] = AssistantChatHistory.messages;
  @State input: string = '';
  @State sending: boolean = false;
  @State settingsOpen: boolean = false;
  @State headerFadeOpacity: number = 0;
  @State composerFadeOpacity: number = 1;
  @State provider: AssistantProvider = AssistantProvider.DEEPSEEK;
  @State apiKeyDraft: string = '';
  @State cloudReady: boolean = false;
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  @StorageProp('hita_nav_bar_vp') navBarInset: number = NAV_BAR_INSET_FALLBACK;
  @StorageProp('hita_keyboard_vp') keyboardInset: number = KEYBOARD_INSET_FALLBACK;
  private settings: AssistantSettings = new AssistantSettings();
  private scroller: Scroller = new Scroller();
  private composerController: TextInputController = new TextInputController();
  private settingsKeyController: TextInputController = new TextInputController();

  async aboutToAppear(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    const store: AssistantSettingsStore = AssistantSettingsStore.getInstance();
    await store.init(ctx);
    this.applySettings(await store.load());
    if (this.messages.length > 1) {
      setTimeout(() => {
        this.scroller.scrollEdge(Edge.Bottom);
      }, 50);
    }
  }

  private applySettings(settings: AssistantSettings): void {
    this.settings = settings;
    this.provider = settings.provider;
    this.apiKeyDraft = settings.apiKey;
    this.cloudReady = settings.hasCloudModel();
  }

  private async saveSettings(): Promise<void> {
    const next: AssistantSettings = new AssistantSettings();
    next.provider = this.provider;
    next.apiKey = this.apiKeyDraft.trim();
    await AssistantSettingsStore.getInstance().save(next);
    this.applySettings(next);
    this.settingsOpen = false;
    this.getUIContext().getPromptAction().showToast({
      message: next.hasCloudModel() ? '已启用 ' + AssistantSettings.providerName(next.provider) : '已切换为仅本地课表问答'
    });
  }

  private setMessages(messages: AssistantMessage[]): void {
    AssistantChatHistory.messages = messages;
    this.messages = messages;
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }

  private clearChat(): void {
    if (this.sending) {
      return;
    }
    this.setMessages([AssistantService.welcome()]);
  }

  private inputBarBottom(): number {
    if (this.keyboardInset > 8) {
      return this.keyboardInset;
    }
    return DOCK_CLEARANCE + this.navBarInset;
  }

  private headerChromeHeight(): number {
    return HEADER_BODY + this.statusBarInset;
  }

  private inputChromeHeight(): number {
    return 58;
  }

  private updateFades(): void {
    this.headerFadeOpacity = HeaderFade.opacity(this.scroller.currentOffset().yOffset);
  }

  private dismissKeyboard(): void {
    this.composerController.stopEditing();
    this.settingsKeyController.stopEditing();
    this.getUIContext().getFocusController().clearFocus();
  }

  private async send(raw: string): Promise<void> {
    const text: string = raw.trim();
    if (text.length === 0 || this.sending) {
      return;
    }
    const history: AssistantMessage[] = this.messages.slice();
    this.input = '';
    this.sending = true;
    this.setMessages(history.concat([AssistantMessage.of(AssistantRole.USER, text)]));
    let reply: AssistantMessage;
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      reply = await AssistantService.reply(ctx, this.settings, history, text);
    } catch (e) {
      reply = AssistantMessage.of(AssistantRole.ASSISTANT, '出了点问题，请稍后再试。');
    }
    this.sending = false;
    this.setMessages(this.messages.concat([reply]));
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Top }) {
        Scroll(this.scroller) {
          Column({ space: 12 }) {
            Blank().height(this.headerChromeHeight());
            if (this.settingsOpen) {
              this.settingsPanel();
            }
            ForEach(this.messages, (message: AssistantMessage) => {
              this.bubble(message);
            }, (message: AssistantMessage) => message.id);
            if (this.sending) {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(COLOR_PRIMARY);
                Text('思考中…')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY);
              }
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .backgroundColor(COLOR_CARD)
              .borderRadius(16);
            }
            if (this.messages.length <= 1 && !this.sending) {
              this.suggestions();
            }
            Blank().height(this.inputChromeHeight());
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 });
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .onDidScroll(() => {
          this.updateFades();
        })
        .onClick(() => {
          this.dismissKeyboard();
        });

        HeaderFadeMask({
          maskOpacity: this.headerFadeOpacity,
          rgb: SURFACE_RGB,
          headerHeight: this.headerChromeHeight()
        });

        HeaderFadeMask({
          maskOpacity: this.composerFadeOpacity,
          rgb: SURFACE_RGB,
          headerHeight: this.inputChromeHeight(),
          fromBottom: true
        })
          .width('100%')
          .align(Alignment.Bottom);

        Row() {
          Text('助手')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          this.headerButton($r('sys.symbol.trash'), '清空对话', () => {
            this.clearChat();
          });
          this.headerButton($r('sys.symbol.gearshape'), '助手设置', () => {
            this.settingsOpen = !this.settingsOpen;
            if (this.settingsOpen) {
              this.provider = this.settings.provider;
              this.apiKeyDraft = this.settings.apiKey;
            }
          });
        }
        .width('100%')
        .height(this.headerChromeHeight())
        .padding({ left: 16, right: 16, top: this.statusBarInset })
        .alignItems(VerticalAlign.Center);
      }
      .width('100%')
      .layoutWeight(1);

      this.inputBar();
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  headerButton(symbol: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(symbol)
        .fontSize(18)
        .fontColor([COLOR_PRIMARY]);
    }
    .width(40)
    .height(40)
    .margin({ left: 8 })
    .backgroundColor(COLOR_NAV_ACTIVE)
    .accessibilityText(label)
    .onClick(action);
  }

  @Builder
  settingsPanel() {
    Column() {
      Text('云端大模型（可选）')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY);
      Text('课表问题始终由本地数据回答；填写 API Key 后，其他问题会连同未来 7 天课表摘要发送给所选模型。')
        .fontSize(12)
        .fontColor(COLOR_TEXT_SECONDARY)
        .lineHeight(18)
        .margin({ top: 4 });
      Row({ space: 4 }) {
        this.providerOption(AssistantProvider.DEEPSEEK);
        this.providerOption(AssistantProvider.ZHIPU);
      }
      .width('100%')
      .padding(4)
      .backgroundColor('#EAF0F7')
      .borderRadius(14)
      .margin({ top: 12 });
      TextInput({ placeholder: this.provider === AssistantProvider.ZHIPU ? '智谱开放平台 API Key' : 'DeepSeek API Key',
        text: this.apiKeyDraft, controller: this.settingsKeyController })
        .type(InputType.Password)
        .height(42)
        .margin({ top: 10 })
        .backgroundColor('#F4F7FC')
        .borderRadius(12)
        .onChange((value: string) => {
          this.apiKeyDraft = value;
        });
      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontColor(COLOR_PRIMARY)
          .backgroundColor(COLOR_NAV_ACTIVE)
          .onClick(() => {
            this.settingsOpen = false;
          });
        Button('保存')
          .layoutWeight(1)
          .height(40)
          .fontColor('#FFFFFF')
          .backgroundColor(COLOR_PRIMARY)
          .onClick(() => {
            this.saveSettings();
          });
      }
      .width('100%')
      .margin({ top: 12 });
    }
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(COLOR_CARD)
    .borderRadius(16);
  }

  @Builder
  providerOption(provider: AssistantProvider) {
    Text(AssistantSettings.providerName(provider))
      .fontSize(14)
      .fontWeight(this.provider === provider ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.provider === provider ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(34)
      .borderRadius(10)
      .backgroundColor(this.provider === provider ? COLOR_CARD : 'transparent')
      .onClick(() => {
        this.provider = provider;
      });
  }

  @Builder
  bubble(message: AssistantMessage) {
    if (message.role === AssistantRole.USER) {
      Row() {
        Blank();
        Text(message.content)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .lineHeight(22)
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor(COLOR_PRIMARY)
          .borderRadius(16)
          .constraintSize({ maxWidth: '82%' })
          .copyOption(CopyOptions.LocalDevice);
      }
      .width('100%');
    } else {
      Column() {
        Text(message.content)
          .fontSize(15)
          .fontColor(COLOR_TEXT_PRIMARY)
          .lineHeight(22)
          .copyOption(CopyOptions.LocalDevice);
        if (message.source.length > 0) {
          Text('来自 ' + message.source)
            .fontSize(11)
            .fontColor(COLOR_TEXT_HINT)
            .margin({ top: 6 });
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(COLOR_CARD)
      .borderRadius(16)
      .constraintSize({ maxWidth: '88%' });
    }
  }

  @Builder
  suggestions() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(AssistantService.SUGGESTIONS, (suggestion: string) => {
        Text(suggestion)
          .fontSize(13)
          .fontColor(COLOR_PRIMARY)
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .backgroundColor(COLOR_NAV_ACTIVE)
          .borderRadius(16)
          .margin({ right: 8, bottom: 8 })
          .onClick(() => {
            this.send(suggestion);
          });
      }, (suggestion: string) => suggestion);
    }
    .width('100%');
  }

  @Builder
  inputBar() {
    Row({ space: 8 }) {
      TextInput({ placeholder: '问问课表，比如“明天有什么课”', text: this.input,
        controller: this.composerController })
        .layoutWeight(1)
        .height(44)
        .backgroundColor(COLOR_CARD)
        .borderRadius(22)
        .padding({ left: 16, right: 16 })
        .enterKeyType(EnterKeyType.Send)
        .onChange((value: string) => {
          this.input = value;
        })
        .onSubmit(() => {
          this.send(this.input);
        });
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.paperplane_fill'))
          .fontSize(18)
          .fontColor(['#FFFFFF']);
      }
      .width(44)
      .height(44)
      .backgroundColor(this.input.trim().length > 0 && !this.sending ? COLOR_PRIMARY : '#AFC8E8')
      .enabled(this.input.trim().length > 0 && !this.sending)
      .accessibilityText('发送')
      .onClick(() => {
        this.send(this.input);
      });
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 8 + this.inputBarBottom() });
  }
}
