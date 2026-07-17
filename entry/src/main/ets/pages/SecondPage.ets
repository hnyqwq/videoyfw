import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';

import { DocScanPage } from '../YYTB/DocScan/DocScanPage';
import { WindowInfo } from '../utils/WindowInfo';

@Entry
@Component
export struct SecondPage {
  context: common.Context = getContext(this);
  @StorageProp('topRectHeight')
  topRectHeight: number = 0;
  @StorageLink('isImmersiveStatusBar')
  isImmersiveStatusBar: boolean = false;
  @StorageProp('bottomRectHeight')
  bottomRectHeight: number = 0;
  @StorageLink('isImmersiveTab')
  isImmersiveTab: boolean = false;
  @ObjectLink mainWindowInfo: WindowInfo;

  private imageSource: image.ImageSource | undefined = undefined;
  @State chooseImage: PixelMap | undefined = undefined;
  @State dataValues: string = '';
  @Provide('pathStack') pathStack: NavPathStack = new NavPathStack()

  @Builder
  PageMap(name: string) {
    if (name === 'documentScanner') {
      DocScanPage()
    }
  }

  private async selectImage() {
    let uri = await this.openPhoto();
    if (uri === undefined) {
      hilog.error(0x0000, 'SecondPage', "Failed to get uri.");
      return;
    }
    this.loadImage(uri);
  }

  private openPhoto(): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      let photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      photoPicker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      }).then((res: photoAccessHelper.PhotoSelectResult) => {
        resolve(res.photoUris[0]);
      }).catch((err: BusinessError) => {
        hilog.error(0x0000, 'SecondPage', `Failed to get photo image uri. code：${err.code}，message：${err.message}`);
        reject('');
      })
    })
  }

  private async loadImage(uri: string) {
    try {
      if (this.chooseImage) {
        this.chooseImage.release();
      }

      let fileSource = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      this.imageSource = image.createImageSource(fileSource.fd);
      this.chooseImage = await this.imageSource.createPixelMap();
      this.dataValues = '';
    } catch (error) {
      hilog.error(0x0000, 'SecondPage', `Image load failed: ${JSON.stringify(error)}`);
    }
  }

  @Builder
  MyTestMenu() {
    Menu() {
      MenuItem({
        startIcon: $r("app.media.CIcon"),
        content: $r('app.string.pickphotos'),
        builder: (): void => {
          this.selectImage();
        }
      })
    }
  }

  // 手机端Menu：仅跨设备协作（仅图片）
  @Builder
  PhonePickMenu() {
    Menu() {
      // 本地选择
      MenuItem({
        startIcon: $r("app.media.CIcon"),
        content: $r('app.string.pickphotos'),
        builder: (): void => {
          this.selectImage();
        }
      })
    }
  }

  scroller: Scroller = new Scroller()

  async aboutToDisappear(): Promise<void> {
    // 释放图像资源
    if (this.chooseImage) {
      this.chooseImage.release();
      this.chooseImage = undefined;
    }
  }

  build() {
    Column() {
      // 顶部避让状态栏
      if (!this.isImmersiveStatusBar) {
        Column()
          .height(px2vp(this.topRectHeight))
      }

      if (this.chooseImage) {
        Row() {
          Button($r('app.string.pick'))
              .type(ButtonType.Capsule)
              .fontColor(Color.White)
              .width('20%')
              .margin({ right: 10 })
              .height(50)
              .backgroundColor($r('sys.color.ohos_id_color_activated'))
              .onClick(() => {
                this.selectImage();
              })
          Button('×')
            .type(ButtonType.Capsule)
            .fontColor(Color.White)
            .alignSelf(ItemAlign.Center)
            .width('20%')
            .height(50)
            .backgroundColor($r('sys.color.ohos_id_color_activated'))
            .onClick(() => {
              this.chooseImage = undefined;
              this.dataValues = '';
            })
        }
        .padding({ top: 5 })

        Stack({ alignContent: Alignment.TopStart }) {
          Scroll(this.scroller) {
            Column() {
              Text(this.dataValues)
                .copyOption(CopyOptions.LocalDevice)
                .width('100%')
                .fontColor($r('sys.color.font_primary'))
              Image(this.chooseImage)
                .objectFit(ImageFit.Auto)
            }
            .width('100%')
            .padding({ bottom: px2vp(this.bottomRectHeight) + (this.isImmersiveTab ? 84 : 0) })
          }
          .scrollable(ScrollDirection.Vertical)
          .scrollBar(BarState.On)
          .scrollBarColor(Color.Gray)
          .scrollBarWidth(5)
          .friction(0.6)
          .edgeEffect(EdgeEffect.None)
          .flexGrow(1)
          .layoutWeight(1)
          .expandSafeArea([SafeAreaType.SYSTEM])
        }
      } else {
        // 无图片时：功能区域上下居中
        Column() {
          Row() {
            Button($r('app.string.pick'))
                .type(ButtonType.Capsule)
                .fontColor(Color.White)
                .width('20%')
                .margin({ right: 10 })
                .height(50)
                .backgroundColor($r('sys.color.ohos_id_color_activated'))
                .onClick(() => {
                  this.selectImage();
                })

          }
          .padding({ top: 5 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  doInsertPicture(stateCode: number, bufferType: string, buffer: ArrayBuffer): void {
    if (stateCode != 0) {
      return;
    }
    if (bufferType == "general.image") {
      let imgSource = image.createImageSource(buffer);
      imgSource.createPixelMap().then((pixelMap: image.PixelMap) => {
        this.chooseImage = pixelMap;
        this.dataValues = '';

        this.imageSource = imgSource;
      }).catch((error: BusinessError) => {
        hilog.error(0x0000, 'SecondPage', `Failed to process image from other device: ${JSON.stringify(error)}`);
      });
    }
  }
}
