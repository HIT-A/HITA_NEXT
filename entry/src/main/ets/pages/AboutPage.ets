/**
 * AboutPage.ets — 关于 / 许可（HITA_X ui/about 语义 → ArkUI）。
 *
 * 内容：项目定位、移植来源、许可与致谢、路线说明。纯展示页。
 */
import { router } from '@kit.ArkUI';

@Entry
@Component
struct AboutPage {
  build() {
    Column() {
      // ── Header bar ──
      Row() {
        Text('<')
          .fontSize(22)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })

        Text('关于')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
          .margin({ left: 4 })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 16 })
      .backgroundColor('#3390EC')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          Text('HITA · HarmonyOS NEXT')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1A1A1A')
            .margin({ top: 30, bottom: 6 })
          Text('HitaNEXT v0.1.0 · 移植预览')
            .fontSize(13)
            .fontColor('#8A8F99')

          Text('本应用为开源项目 HITA_X（StupidTrees）功能 × 新版 HITA 登录规格整合移植至' +
            ' HarmonyOS NEXT 的实现蓝本 v1.0 的工程落地。')
            .fontSize(14)
            .fontColor('#333333')
            .lineHeight(24)
            .width('90%')
            .margin({ top: 24 })

          this.item('项目定位', '哈工大三校区（深圳/本部/威海）课表/日程/成绩等校园工具；' +
            '不含 θ社区/云端账号/同步（默认裁剪）。')
          this.item('移植来源', 'HITA_X 源码镜像（.kt，346 文件）与新版 HITA APK 反编译规格，' +
            '逐文件映射见 docs/mapping-hitax-to-arkts.md。')
          this.item('登录形态', 'ArkWeb 网页登录 + Cookie 会话（对应新版 EASToken）；判定谓词为纯函数，可回归。')
          this.item('状态说明', '登录与数据接口需真机/抓包联调（M0/M2）；本地课表/时间线/事件/样例成绩可离线运行。')
          this.item('致谢', '哈工大开源社区 HITA 系开发者；数据版权归哈尔滨工业大学各校区教务。')

          Text('许可：仅限学习研究，请遵守校方条款与开源许可。')
            .fontSize(12)
            .fontColor('#B0B4BA')
            .width('90%')
            .margin({ top: 24 })

          Button('返回')
            .width('90%')
            .height(42)
            .margin({ top: 24, bottom: 40 })
            .backgroundColor('#3390EC')
            .borderRadius(21)
            .onClick(() => {
              this.getUIContext().getRouter().back();
            })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#FFFFFF')
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  item(title: string, body: string) {
    Column() {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#3390EC')
        .alignSelf(ItemAlign.Start)
      Text(body)
        .fontSize(13)
        .fontColor('#555555')
        .lineHeight(22)
        .textAlign(TextAlign.Start)
        .width('100%')
        .margin({ top: 4 })
    }
    .width('90%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 14 })
  }
}
