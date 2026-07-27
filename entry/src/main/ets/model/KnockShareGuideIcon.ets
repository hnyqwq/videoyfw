import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import Logger from '../utils/Logger';

const LOGO_IMG_LENGTH: number = 63;
const DURATION: number = 34; // 1000ms/30fps
const ICON_URL_PREFIX: string = 'https://app.hnyqwq.cn/hvideo/knock/knock_share_guide_icon_';

const logger = Logger.getLogger('[KnockShareGuideIcon]');
const MAX_CONCURRENT_REQUESTS = 6;

// 模块级缓存：所有图标实例共享，避免重复下载
const iconFrameCache = new Map<string, ImageFrameInfo>();

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
const iconLimiter = new Semaphore(MAX_CONCURRENT_REQUESTS);

@Component
export default struct KnockShareGuideIcon {
  @Prop iconSize: number = 20;
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
    this.animFrames = [];
    this.animReady = false;
  }

  private async loadPixels(): Promise<void> {
    const tasks: Promise<ImageFrameInfo>[] = [];
    for (let i = 1; i <= LOGO_IMG_LENGTH; i++) {
      tasks.push(this.loadByNetwork(i));
    }
    const results = await Promise.all(tasks);
    if (!this.isCancelled) {
      this.animFrames = results;
    }
  }

  private async loadByNetwork(index: number): Promise<ImageFrameInfo> {
    const url = `${ICON_URL_PREFIX}${index}.png`;

    // 命中缓存直接返回
    const cached = iconFrameCache.get(url);
    if (cached) {
      return cached;
    }

    await iconLimiter.acquire();
    if (this.isCancelled) {
      iconLimiter.release();
      return { src: url, duration: DURATION };
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
        return { src: url, duration: DURATION };
      }

      if (response.responseCode === 200 && response.result instanceof ArrayBuffer) {
        imageSource = image.createImageSource(response.result);
        const pixelMap = await imageSource.createPixelMap();
        const frameInfo: ImageFrameInfo = { src: pixelMap, duration: DURATION };
        iconFrameCache.set(url, frameInfo);
        return frameInfo;
      }
    } catch (err) {
      logger.error(`Failed to load icon by network: ${err?.code}, ${err?.message}`);
    } finally {
      try { httpRequest.destroy(); } catch (e) { /* ignore */ }
      iconLimiter.release();
    }

    // 降级：返回URL字符串，让ImageAnimator自行加载
    return { src: url, duration: DURATION };
  }

  build() {
    Column() {
      ImageAnimator()
        .images(this.animReady ? this.animFrames : this.staticFrame)
        .state(this.animReady ? AnimationStatus.Running : AnimationStatus.Initial)
        .iterations(-1)
        .width(this.iconSize)
        .height(this.iconSize)
    }
    .justifyContent(FlexAlign.Center)
    .width(this.iconSize * 1.5)
    .height(this.iconSize * 1.5)
    .borderRadius(this.iconSize * 0.375)
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [['#4C99F3', 0], ['#3778EF', 1]]
    })
  }
}
