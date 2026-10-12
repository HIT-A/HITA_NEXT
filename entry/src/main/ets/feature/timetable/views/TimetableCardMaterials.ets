import { ImmersiveHeader } from '../../../common/components/ImmersiveHeader';
import { CompatibleMaterialModifier } from '../../../common/theme/CompatibleMaterialModifier';
import { drawTimetableCardText, TimetableCardSurface } from './TimetableWeekDraw';
import { TimetableCardPainter } from './TimetableCardPainter';
import { DeleteParticleCard } from '../../../common/components/DeleteParticleCard';
import { DeleteEffectController } from '../../../common/util/DeleteEffectController';
import { image } from '@kit.ImageKit';

@Component
struct TimetableMaterialCard {
  @Prop card: TimetableCardSurface = new TimetableCardSurface();
  painter: TimetableCardPainter = new TimetableCardPainter();
  onCardClick: (key: string) => void = () => {};
  private textCanvas: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private placeCanvas: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private placeReady: boolean = false;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Canvas(this.textCanvas)
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
        .onReady(() => { drawTimetableCardText(this.textCanvas, this.card); })
      if (this.card.place !== undefined && this.card.place.textWidth > this.card.place.width) {
        Canvas(this.placeCanvas)
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.None)
          .onReady(() => {
            this.placeReady = true;
            this.painter.attach(this.card, this.placeCanvas);
          })
      }
    }
    .width(this.card.width)
    .height(this.card.height)
    .borderRadius(this.card.radius)
    .backgroundColor(this.card.color)
    .attributeModifier(new CompatibleMaterialModifier(this.card.color, true, true, this.card.tint()))
    // Register the click on the material itself so native press light/deformation can track the finger.
    .onClick(() => this.onCardClick(this.card.key))
    .onAppear(() => {
      if (this.placeReady) {
        this.painter.attach(this.card, this.placeCanvas);
      }
    })
    .onDisAppear(() => { this.painter.detach(this.placeCanvas); });
  }
}

@Component
export struct TimetableCardMaterials {
  @Prop @Watch('onCardsChanged') cards: TimetableCardSurface[] = [];
  @Prop contentHeight: number = 0;
  @State hiddenCardKeys: string[] = [];
  painter: TimetableCardPainter = new TimetableCardPainter();
  deleteEffects: DeleteEffectController = new DeleteEffectController();
  onCardClick: (key: string) => void = () => {};

  private onCardsChanged(): void {
    this.hiddenCardKeys = this.hiddenCardKeys.filter((key: string): boolean =>
      this.cards.some((card: TimetableCardSurface): boolean => card.key === key));
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // Keep the material host separate from the unframed particle overlay.
      ImmersiveHeader({ barHeight: this.contentHeight }) {
        Stack({ alignContent: Alignment.TopStart }) {
          ForEach(this.cards, (card: TimetableCardSurface) => {
            TimetableMaterialCard({ card: card, painter: this.painter, onCardClick: this.onCardClick })
              .position({ x: card.left, y: card.top })
              .opacity(this.hiddenCardKeys.indexOf(card.key) >= 0 ? 0 : 1)
          }, (card: TimetableCardSurface) => card.renderKey());
        }
        .width('100%')
        .height(this.contentHeight)
        .hitTestBehavior(HitTestMode.Transparent);
      }
      Stack({ alignContent: Alignment.TopStart }) {
        ForEach(this.cards, (card: TimetableCardSurface) => {
          Stack({ alignContent: Alignment.TopStart }) {
            DeleteParticleCard({
              controller: this.deleteEffects,
              effectId: card.key,
              captureSource: (density: number): Promise<image.PixelMap> => this.painter.capture(card, density),
              onSourceHidden: () => {
                if (this.hiddenCardKeys.indexOf(card.key) < 0) {
                  this.hiddenCardKeys = this.hiddenCardKeys.concat([card.key]);
                }
              }
            }) {
              // Geometry only: the original visible card stays in the material host.
              Blank().width(card.width).height(card.height).hitTestBehavior(HitTestMode.None);
            }
          }
          .width(card.width)
          .height(card.height)
          .position({ x: card.left, y: card.top })
          .clip(false)
        }, (card: TimetableCardSurface) => card.renderKey());
      }
      .width('100%')
      .height(this.contentHeight)
      .clip(false)
      // None excludes only this Stack: snapshot containers would still cover the live material.
      .hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS);
    }
    .width('100%')
    .height(this.contentHeight)
    .clip(false)
    .accessibilityLevel('no-hide-descendants')
    .hitTestBehavior(HitTestMode.Transparent);
  }
}
