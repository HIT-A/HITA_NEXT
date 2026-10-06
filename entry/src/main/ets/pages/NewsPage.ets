/**
 * NewsPage.ets — 功能中心「资讯」：博客与通知。
 */
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { HeaderFadeMask } from '../common/components/HeaderFadeMask';
import { HeaderFade } from '../common/theme/HeaderFade';
import { NAV_BAR_INSET_FALLBACK, STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { NewsCategory, NewsItem, NewsPage as NewsPageResult, NewsService } from '../feature/news/NewsService';

const COLOR_PRIMARY: ResourceColor = $r('app.color.hita_primary');
const SURFACE_RGB: string = '244,247,252';
const COLOR_CARD: ResourceColor = $r('app.color.hita_surface');
const COLOR_TEXT_PRIMARY: ResourceColor = $r('app.color.hita_text');
const COLOR_TEXT_SECONDARY: ResourceColor = $r('app.color.hita_text_secondary');
const COLOR_TEXT_HINT: ResourceColor = $r('app.color.hita_text_secondary_5a6880');
const COLOR_NAV_ACTIVE: ResourceColor = $r('app.color.hita_selected');

@Entry
@Component
struct NewsPage {
  @State selected: number = 0;
  @State items: NewsItem[] = [];
  @State loading: boolean = false;
  @State refreshing: boolean = false;
  @State hasMore: boolean = true;
  @State message: string = '';
  @State fadeOpacity: number = 0;
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  @StorageProp('hita_nav_bar_vp') navBarInset: number = NAV_BAR_INSET_FALLBACK;
  private page: number = 0;
  private generation: number = 0;
  private newsScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.reload();
  }

  aboutToDisappear(): void {
    this.generation++;
  }

  private selectTab(index: number): void {
    if (index < 0 || index >= NewsService.CATEGORIES.length || this.selected === index) {
      return;
    }
    this.selected = index;
    this.fadeOpacity = 0;
    this.newsScroller.scrollEdge(Edge.Top);
    this.reload();
  }

  private async reload(): Promise<void> {
    this.generation++;
    this.page = 0;
    this.items = [];
    this.fadeOpacity = 0;
    this.hasMore = true;
    this.message = '';
    const generation: number = this.generation;
    await this.loadPage();
    if (generation === this.generation) {
      this.refreshing = false;
    }
  }

  private async loadPage(): Promise<void> {
    if (this.loading && this.page > 0) {
      return;
    }
    const generation: number = this.generation;
    const category: NewsCategory = NewsService.CATEGORIES[this.selected];
    this.loading = true;
    const result: NewsPageResult = await NewsService.fetchCategory(category.id, this.page);
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
    this.hasMore = result.hasMore && fresh.length > 0;
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
        HeaderBackButton({
          onBack: () => this.getUIContext().getRouter().back()
        })
          .margin({ right: 12 });
        Column() {
          Text('资讯')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_PRIMARY);
          Text('博客与通知')
            .fontSize(12)
            .fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 2 });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
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
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 + this.statusBarInset, bottom: 8 })
      .alignItems(VerticalAlign.Center);

      Column() {
        Row({ space: 4 }) {
          ForEach(NewsService.CATEGORIES, (category: NewsCategory, index: number) => {
            this.segment(category.name, index);
          }, (category: NewsCategory) => category.id);
        }
        .width('100%')
        .padding(4)
        .backgroundColor($r('app.color.hita_control_eaf0f7'))
        .borderRadius(16);
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 });

      this.newsList();
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.hita_page'))
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
          ListItem() {
            Column().height(12 + this.navBarInset);
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

}
