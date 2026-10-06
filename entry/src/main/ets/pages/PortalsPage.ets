import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { HeaderFadeMask } from '../common/components/HeaderFadeMask';
import { HeaderFade } from '../common/theme/HeaderFade';
import { NAV_BAR_INSET_FALLBACK, STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { CampusPortal, CampusPortalGroup } from '../feature/portal/CampusPortal';

const HEADER_HEIGHT: number = 60;
const PAGE_BG: ResourceColor = $r('app.color.hita_page');
const PAGE_BG_RGB: string = '244,247,252';
const COLOR_PRIMARY: ResourceColor = $r('app.color.hita_primary');
const COLOR_TEXT_PRIMARY: ResourceColor = $r('app.color.hita_text');
const COLOR_TEXT_SECONDARY: ResourceColor = $r('app.color.hita_text_secondary');

@Entry
@Component
struct PortalsPage {
  @State fadeOpacity: number = 0;
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  @StorageProp('hita_nav_bar_vp') navBarInset: number = NAV_BAR_INSET_FALLBACK;
  private listScroller: Scroller = new Scroller();

  private open(portal: CampusPortal): void {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/WebBrowserPage',
      params: { 'url': portal.url, 'title': portal.title }
    });
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      this.portalList();

      HeaderFadeMask({ maskOpacity: this.fadeOpacity, rgb: PAGE_BG_RGB, headerHeight: HEADER_HEIGHT });

      Row() {
        HeaderBackButton({
          onBack: () => this.getUIContext().getRouter().back()
        })
          .margin({ right: 12 });
        Text('常用入口')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_PRIMARY)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .width('100%')
      .height(HEADER_HEIGHT)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent);
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarInset })
    .backgroundColor(PAGE_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }

  @Builder
  portalList() {
    List({ space: 10, scroller: this.listScroller }) {
      ListItem() {
        Column().width('100%').height(HEADER_HEIGHT);
      }
      ForEach(CampusPortal.GROUPS, (group: CampusPortalGroup) => {
        ListItemGroup({ header: this.groupHeader(group.title), space: 10 }) {
          ForEach(group.portals, (portal: CampusPortal) => {
            ListItem() {
              this.portalRow(portal);
            }
          }, (portal: CampusPortal) => portal.url);
        }
      }, (group: CampusPortalGroup) => group.title);
      ListItem() {
        Column().height(12 + this.navBarInset);
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16 })
    .scrollBar(BarState.Off)
    .onDidScroll(() => {
      this.fadeOpacity = HeaderFade.opacity(this.listScroller.currentOffset().yOffset);
    });
  }

  @Builder
  groupHeader(title: string) {
    Text(title)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor(COLOR_TEXT_PRIMARY)
      .width('100%')
      .padding({ top: 8, bottom: 12 });
  }

  @Builder
  portalRow(portal: CampusPortal) {
    Row() {
      Stack() {
        SymbolGlyph($r('sys.symbol.link'))
          .fontSize(20)
          .fontColor([COLOR_PRIMARY]);
      }
      .width(40)
      .height(40)
      .flexShrink(0)
      .borderRadius(20)
      .backgroundColor($r('app.color.hita_selected'))
      .alignContent(Alignment.Center);
      Column() {
        Text(portal.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY);
        Text(portal.subtitle)
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .margin({ top: 3 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12, right: 12 });
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([COLOR_TEXT_SECONDARY])
        .flexShrink(0);
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.hita_surface'))
    .borderRadius(16)
    .onClick(() => {
      this.open(portal);
    });
  }
}
