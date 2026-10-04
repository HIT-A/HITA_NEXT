/**
 * NewsTab.ets — 主页「资讯」栏：今日哈工大公告/新闻 + 常用校园入口。
 */
import { HeaderFadeMask } from '../../common/components/HeaderFadeMask';
import { HeaderFade } from '../../common/theme/HeaderFade';
import { STATUS_BAR_INSET_FALLBACK } from '../../common/theme/StatusBarInset';
import { NewsCategory, NewsItem, NewsPage, NewsPortal, NewsService } from './NewsService';

const COLOR_PRIMARY: string = '#2E86E8';
const SURFACE_RGB: string = '244,247,252';
const COLOR_CARD: string = '#FFFFFF';
const COLOR_TEXT_PRIMARY: string = '#14213D';
const COLOR_TEXT_SECONDARY: string = '#4E5C72';
const COLOR_TEXT_HINT: string = '#5A6880';
const COLOR_NAV_ACTIVE: string = '#E3EEFC';
const PORTAL_TAB: number = NewsService.CATEGORIES.length;

@Component
export struct NewsTab {
  @State selected: number = 0;
  @State items: NewsItem[] = [];
  @State loading: boolean = false;
  @State refreshing: boolean = false;
  @State hasMore: boolean = true;
  @State message: string = '';
  @State fadeOpacity: number = 0;
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  private page: number = 0;
  private generation: number = 0;
  private newsScroller: Scroller = new Scroller();
  private portalScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.reload();
  }

  private selectTab(index: number): void {
    if (this.selected === index) {
      return;
    }
    this.selected = index;
    this.fadeOpacity = 0;
    if (index < PORTAL_TAB) {
      this.reload();
    }
  }

  private async reload(): Promise<void> {
    this.generation++;
    this.page = 0;
    this.items = [];
    this.fadeOpacity = 0;
    this.hasMore = true;
    this.message = '';
    await this.loadPage();
    this.refreshing = false;
  }

  private async loadPage(): Promise<void> {
    if (this.selected >= PORTAL_TAB || (this.loading && this.page > 0)) {
      return;
    }
    const generation: number = this.generation;
    const category: NewsCategory = NewsService.CATEGORIES[this.selected];
    this.loading = true;
    const result: NewsPage = await NewsService.fetchCategory(category.id, this.page);
    if (generation !== this.generation) {
      return;
    }
    this.loading = false;
    if (!result.ok) {
      this.message = result.message;
      this.hasMore = false;
      return;
    }
    const known: Set<string> = new Set<string>(this.items.map((item: NewsItem): string => item.url));
    const fresh: NewsItem[] = result.items.filter((item: NewsItem): boolean => !known.has(item.url));
    this.items = this.items.concat(fresh);
    this.hasMore = fresh.length > 0;
    this.page++;
    this.message = this.items.length === 0 ? (result.message.length > 0 ? result.message : '暂无资讯') : '';
  }

  private open(url: string, title: string): void {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/WebBrowserPage',
      params: { 'url': url, 'title': title }
    });
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text('资讯')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_PRIMARY);
          Text('今日哈工大 · 校园公告与新闻')
            .fontSize(12)
            .fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 2 });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
        if (this.selected < PORTAL_TAB) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(18)
              .fontColor([COLOR_PRIMARY]);
          }
          .width(40)
          .height(40)
          .backgroundColor(COLOR_NAV_ACTIVE)
          .enabled(!this.loading)
          .accessibilityText('刷新')
          .onClick(() => {
            this.reload();
          });
        }
      }
      .width('100%')
      .padding({ left: 20, right: 16, top: 14 + this.statusBarInset, bottom: 8 })
      .alignItems(VerticalAlign.Center);

      Column() {
        Row({ space: 4 }) {
          ForEach(NewsService.CATEGORIES, (category: NewsCategory, index: number) => {
            this.segment(category.name, index);
          }, (category: NewsCategory) => category.id);
          this.segment('常用入口', PORTAL_TAB);
        }
        .width('100%')
        .padding(4)
        .backgroundColor('#EAF0F7')
        .borderRadius(16);
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 });

      if (this.selected >= PORTAL_TAB) {
        this.portalList();
      } else {
        this.newsList();
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }

  @Builder
  segment(label: string, index: number) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.selected === index ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.selected === index ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(36)
      .borderRadius(12)
      .backgroundColor(this.selected === index ? COLOR_CARD : 'transparent')
      .onClick(() => {
        this.selectTab(index);
      });
  }

  @Builder
  newsList() {
    Stack({ alignContent: Alignment.Top }) {
      Refresh({ refreshing: $$this.refreshing }) {
        List({ space: 10, scroller: this.newsScroller }) {
          ForEach(this.items, (item: NewsItem) => {
            ListItem() {
              this.newsRow(item);
            }
          }, (item: NewsItem) => item.url);
          ListItem() {
            this.listFooter();
          }
        }
        .width('100%')
        .height('100%')
        .padding({ left: 16, right: 16 })
        .scrollBar(BarState.Off)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .onDidScroll(() => {
          this.fadeOpacity = HeaderFade.opacity(this.newsScroller.currentOffset().yOffset);
        })
        .onReachEnd(() => {
          if (this.hasMore && !this.loading && this.items.length > 0) {
            this.loadPage();
          }
        });
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .onRefreshing(() => {
        this.reload();
      });

      HeaderFadeMask({ maskOpacity: this.fadeOpacity, rgb: SURFACE_RGB });
    }
    .width('100%')
    .layoutWeight(1)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }

  @Builder
  listFooter() {
    Column() {
      if (this.loading) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(COLOR_PRIMARY);
          Text(this.items.length === 0 ? '正在加载资讯…' : '正在加载更多…')
            .fontSize(13)
            .fontColor(COLOR_TEXT_HINT);
        }
      } else if (this.message.length > 0) {
        Text(this.message)
          .fontSize(13)
          .fontColor(COLOR_TEXT_HINT);
        Button('重试')
          .fontSize(14)
          .height(36)
          .fontColor(COLOR_PRIMARY)
          .backgroundColor(COLOR_NAV_ACTIVE)
          .borderRadius(18)
          .margin({ top: 10 })
          .onClick(() => {
            this.reload();
          });
      } else if (!this.hasMore && this.items.length > 0) {
        Text('没有更多了')
          .fontSize(12)
          .fontColor(COLOR_TEXT_HINT);
      }
    }
    .width('100%')
    .padding({ top: 12 })
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  newsRow(item: NewsItem) {
    Column() {
      Text(item.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY)
        .lineHeight(22)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
      Row() {
        if (item.department.length > 0) {
          Text(item.department)
            .fontSize(11)
            .fontColor(COLOR_PRIMARY)
            .backgroundColor(COLOR_NAV_ACTIVE)
            .borderRadius(9)
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '60%' });
        }
        Blank();
        Text(item.date)
          .fontSize(12)
          .fontColor(COLOR_TEXT_HINT);
      }
      .width('100%')
      .margin({ top: 8 });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 14, bottom: 12 })
    .backgroundColor(COLOR_CARD)
    .borderRadius(16)
    .onClick(() => {
      this.open(item.url, item.title);
    });
  }

  @Builder
  portalList() {
    Stack({ alignContent: Alignment.Top }) {
      this.portalItems();
      HeaderFadeMask({ maskOpacity: this.fadeOpacity, rgb: SURFACE_RGB });
    }
    .width('100%')
    .layoutWeight(1)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }

  @Builder
  portalItems() {
    List({ space: 10, scroller: this.portalScroller }) {
      ForEach(NewsService.PORTALS, (portal: NewsPortal) => {
        ListItem() {
          Row() {
            Stack() {
              SymbolGlyph($r('sys.symbol.doc_text'))
                .fontSize(20)
                .fontColor([COLOR_PRIMARY]);
            }
            .width(40)
            .height(40)
            .borderRadius(20)
            .backgroundColor(COLOR_NAV_ACTIVE)
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
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 });
            Text('›')
              .fontSize(23)
              .fontColor(COLOR_TEXT_SECONDARY);
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .backgroundColor(COLOR_CARD)
          .borderRadius(16)
          .onClick(() => {
            this.open(portal.url, portal.title);
          });
        }
      }, (portal: NewsPortal) => portal.url);
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16 })
    .scrollBar(BarState.Off)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .onDidScroll(() => {
      this.fadeOpacity = HeaderFade.opacity(this.portalScroller.currentOffset().yOffset);
    });
  }
}
