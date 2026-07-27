import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { LengthMetrics } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import Logger from '../utils/Logger';
import KnockShareGuideIcon from './KnockShareGuideIcon';

const GUIDE_CARD_MULTIPLE_MIN_HEIGHT = 90;
const GUIDE_CARD_SINGLE_MIN_HEIGHT = 80;

const logger = Logger.getLogger('[KnockShareGuideCard]');
const MAX_CONCURRENT_REQUESTS = 6;

// 模块级缓存：所有卡片实例共享，避免重复下载
const frameCache = new Map<string, ImageFrameInfo>();

// 并发限流器，防止瞬间发起数百个HTTP请求导致libhttp CFI崩溃
class Semaphore {
  private max: number;
  private running = 0;
  private waiters: (() => void)[] = [];
  constructor(max: number) {
    this.max = max;
  }
  async acquire(): Promise<void> {
    if (this.running < this.max) { this.running++; return; }
    await new Promise<void>(res => this.waiters.push(() => { this.running++; res(); }));
  }
  release(): void {
    this.running--;
    const next = this.waiters.shift();
    if (next) next();
  }
}
const limiter = new Semaphore(MAX_CONCURRENT_REQUESTS);

export interface CardRes {
  title: ResourceStr;
  text: ResourceStr;
  urlPrefix: string;
  framesCount: number;
  fps?: number; // default 30
  startDelay?: number; // default 0
  stopDelay?: number; // default 0
}

@Reusable
@Component
export struct KnockShareSingleGuideCard {
  @Prop running: boolean = false;
  @Require res: CardRes;
  @Require minHeight: number;
  @Require hasIndicator: boolean;
  @State animReady: boolean = false;
  private animFrames: ImageFrameInfo[] = [];
  private staticFrame: ImageFrameInfo[] = [];
  private isCancelled: boolean = false;

  aboutToAppear(): void {
    this.isCancelled = false;
    this.loadPixels().then(() => {
      if (!this.isCancelled) {
        this.animReady = true;
      }
    });
  }

  aboutToDisappear(): void {
    this.isCancelled = true;
    // PixelMap由模块级共享缓存管理，组件销毁时仅清空本地引用，避免释放其他实例仍在使用的资源
    this.animFrames = [];
    this.animReady = false;
  }

  @Builder
  tipTextsBuilder() {
    Column({ space: 2 }) {
      Row({ space: 6 }) {
        KnockShareGuideIcon({ iconSize: 14 })
        Text(this.res.title)
          .fontFamily('HarmonyHeiTi')
          .textAlign(TextAlign.Start)
          .fontColor($r('app.color.font_primary'))
          .fontSize($r('sys.float.Body_M'))
          .fontWeight(FontWeight.Medium)
          .lineHeight(19)
          .maxFontScale(1)
          .layoutWeight(1)
      }
      Text() {
        Span(this.res.text)
          .fontColor($r('app.color.font_secondary'))
          .fontWeight(FontWeight.Regular)
      }
      .fontSize(12)
      .minFontSize(10)
      .maxFontSize(12)
      .lineHeight(16)
      .maxLines(3)
      .maxFontScale(1)
      .fontFamily('HarmonyHeiTi')
      .wordBreak(WordBreak.BREAK_WORD)
      .textAlign(TextAlign.Start)
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding({
      start: LengthMetrics.vp(16),
      top: LengthMetrics.vp(12),
      bottom: LengthMetrics.vp(this.hasIndicator ? 24 : 12)
    })
    .id('tips_container')
    .alignRules({
      left: { anchor: '__container__', align: HorizontalAlign.Start },
      right: { anchor: '__container__', align: HorizontalAlign.End },
    })
    .margin({ end: LengthMetrics.vp(this.minHeight * 1.5) })
    .constraintSize({ minHeight: this.minHeight })
    .zIndex(1)
  }

  @Builder
  animSurfaceBuilder() {
    ImageAnimator()
      .images(this.animReady ? this.animFrames : this.staticFrame)
      .aspectRatio(1.5)
      .state(AnimationStatus.Running)
      .iterations(-1)
      .id('knock_share_guide_anim')
      .alignRules({
        center: { anchor: 'tips_container', align: VerticalAlign.Center },
        right: { anchor: '__container__', align: HorizontalAlign.End },
      })
      .margin(0)
      .height(this.minHeight)
      .state((this.animReady && this.running) ? AnimationStatus.Running : AnimationStatus.Paused)
      .accessibilityLevel('no')
  }

  build() {
    RelativeContainer() {
      this.tipTextsBuilder()
      this.animSurfaceBuilder()
    }
    .borderRadius(8)
    .backgroundColor(this.getColor($r('app.color.icon_primary'), 0.02))
    .borderWidth(1)
    .borderColor(this.getColor($r('app.color.icon_primary'), 0.05))
    .clip(true)
    .height('auto')
    .margin({ left: 16, right: 16 })
  }

  private getColor(res: resourceManager.Resource, opacity?: number): resourceManager.Resource | number {
    if (!opacity) {
      return res;
    }
    const uiContext: UIContext = this.getUIContext();
    const contextFaker: Context = uiContext.getHostContext() as Context;
    try {
      let color = contextFaker.resourceManager.getColorSync(res.id);
      if (opacity !== undefined && opacity >= 0 && opacity <= 1) {
        let alpha = 0xFF & ((color & 0xFF000000) >> 24);
        // 在原有透明度基础上进行opacity计算
        alpha = Math.floor(alpha * opacity);
        color = (alpha << 24) | (color & 0x00FFFFFF);
      }
      return color;
    } catch (error) {
      logger.error(`getColorSync error. Code: ${error?.code}, message: ${error?.message}`);
      return res;
    }
  }

  private async loadPixels(): Promise<void> {
    const tasks: Promise<ImageFrameInfo>[] = [];
    for (let i = 1; i <= this.res.framesCount; i++) {
      tasks.push(this.loadByNetwork(i));
    }
    const results = await Promise.all(tasks);
    if (!this.isCancelled) {
      this.animFrames = results;
    }
  }

  private async loadByNetwork(index: number): Promise<ImageFrameInfo> {
    const url = this.getUrl(index);
    const duration = Math.floor(1000 / (this.res.fps ?? 30)) +
      (index === 1 ? (this.res.startDelay ?? 0) : (index === this.res.framesCount ? (this.res.stopDelay ?? 0) : 0));

    // 命中缓存直接返回
    const cached = frameCache.get(url);
    if (cached) {
      return cached;
    }

    await limiter.acquire();
    if (this.isCancelled) {
      limiter.release();
      return { src: url, duration };
    }

    const httpRequest = http.createHttp();
    let imageSource: image.ImageSource | undefined = undefined;

    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 10000,
      });

      if (this.isCancelled) {
        return { src: url, duration };
      }

      if (response.responseCode === 200 && response.result instanceof ArrayBuffer) {
        imageSource = image.createImageSource(response.result);
        const pixelMap = await imageSource.createPixelMap();
        const frameInfo: ImageFrameInfo = { src: pixelMap, duration };
        frameCache.set(url, frameInfo);
        return frameInfo;
      }
    } catch (err) {
      logger.error(`Failed to load by network: ${err?.code}, ${err?.message}`);
    } finally {
      try { httpRequest.destroy(); } catch (e) { /* ignore */ }
      limiter.release();
    }

    // 降级：返回URL字符串，让ImageAnimator自行加载
    return { src: url, duration };
  }

  private getUrl(index: number): string {
    return `${this.res.urlPrefix}${(index).toString().padStart(2, '0')}.png`;
  }
}

@Component
export default struct KnockShareGuideCard {
  @Require cardSwiperResources: CardRes[];
  @Prop isKnockShareSupported: boolean = false;
  @Provide swiperIndex: number = 0;
  private indicatorController: IndicatorComponentController = new IndicatorComponentController();

  aboutToAppear(): void {
    logger.info(`KnockShareGuideCard aboutToAppear: cardSwiperResources.length=${this.cardSwiperResources?.length}, isKnockShareSupported=${this.isKnockShareSupported}`);
  }

  @Builder
  indicatorBuilder() {
    IndicatorComponent()
  }

  build() {
    if (!this.cardSwiperResources || this.cardSwiperResources.length === 0) {
      // 如果没有卡片资源,不渲染任何内容
      Column() {
        Text('卡片资源加载中...')
          .fontSize(12)
          .fontColor('#999999')
      }
      .width('100%')
      .height(100)
    } else if (this.cardSwiperResources.length === 1) {
      KnockShareSingleGuideCard({
        running: true,
        res: this.cardSwiperResources[0],
        minHeight: GUIDE_CARD_SINGLE_MIN_HEIGHT,
        hasIndicator: false,
      })
        .width('100%')
    } else {
      Stack({ alignContent: Alignment.Bottom }) {
        Swiper() {
          ForEach(this.cardSwiperResources, (item: CardRes, index: number) => {
            KnockShareSingleGuideCard({
              running: this.swiperIndex === index,
              res: item,
              minHeight: GUIDE_CARD_MULTIPLE_MIN_HEIGHT,
              hasIndicator: true,
            })
          })
        }
        .constraintSize({ minHeight: GUIDE_CARD_MULTIPLE_MIN_HEIGHT })
        .width('100%')
        .zIndex(2)
        .onChange(index => {
          this.swiperIndex = index;
        })
        .autoPlay(true)
        .interval(7000)
        .loop(true)
        .indicator(false)
        .itemSpace(12)

        Row() {
          ForEach(this.cardSwiperResources, (item: CardRes, index: number) => {
            Circle()
              .width(6)
              .height(6)
              .fill(index === this.swiperIndex ? 0xFF007DFF : 0xFFCCCCCC)
              .margin({ left: 4, right: 4 })
          })
        }
        .height(24)
        .width('100%')
        .zIndex(3)
        .padding(0)
        .justifyContent(FlexAlign.Center)
      }
    }
  }
}
