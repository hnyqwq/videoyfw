import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import Logger from '../utils/Logger';

const LOGO_IMG_LENGTH: number = 63;
const DURATION: number = 34; // 1000ms/30fps
const ICON_URL_PREFIX: string = 'https://app.hnyqwq.cn/hvideo/knock/knock_share_guide_icon_';

const logger = Logger.getLogger('[KnockShareGuideIcon]');

@Component
export default struct KnockShareGuideIcon {
  @Prop iconSize: number = 20;
  @State animReady: boolean = false;
  private animFrames: ImageFrameInfo[] = [];
  private staticFrame: ImageFrameInfo[] = [];

  aboutToAppear(): void {
    this.loadPixels().then(() => {
      this.animReady = true;
    });
  }

  aboutToDisappear(): void {
    this.releaseAnimFrames();
  }

  private releaseAnimFrames(): void {
    for (let frame of this.animFrames) {
      if (frame.src && typeof frame.src !== 'string') {
        try {
          (frame.src as PixelMap).release();
        } catch (e) {
          logger.error(`Failed to release PixelMap: ${e}`);
        }
      }
    }
    this.animFrames = [];
    this.animReady = false;
  }

  private async loadPixels(): Promise<void> {
    const tasks: Promise<ImageFrameInfo>[] = [];
    for (let i = 1; i <= LOGO_IMG_LENGTH; i++) {
      tasks.push(this.loadByNetwork(i));
    }
    this.animFrames = await Promise.all(tasks);
  }

  private async loadByNetwork(index: number): Promise<ImageFrameInfo> {
    const url = `${ICON_URL_PREFIX}${index}.png`;
    let src: string | PixelMap = url;
    let imageSource: image.ImageSource | undefined = undefined;

    try {
      const httpRequest = http.createHttp();
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 10000,
      });

      if (response.responseCode === 200 && response.result instanceof ArrayBuffer) {
        imageSource = image.createImageSource(response.result);
      }
      httpRequest.destroy();
    } catch (err) {
      logger.error(`Failed to load icon by network: ${err?.code}, ${err?.message}`);
    }

    return {
      src: src,
      duration: DURATION,
    };
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
