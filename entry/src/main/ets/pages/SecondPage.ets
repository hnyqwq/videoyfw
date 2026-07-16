import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';

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

  // 手机端多设备开关（默认开启）
  @State isMultiDeviceEnabled: boolean = true;
  private prefs: preferences.Preferences | null = null;

  // 保存多设备开关设置
  async saveMultiDeviceSetting(enabled: boolean) {
    try {
      if (!this.prefs) {
        this.prefs = await preferences.getPreferences(this.context, 'app_settings');
      }
      await this.prefs.put('isMultiDeviceEnabled', enabled);
      await this.prefs.flush();
      hilog.info(0x0000, 'SecondPage', `多设备开关设置已保存: ${enabled}`);
    } catch (err) {
      hilog.error(0x0000, 'SecondPage', `保存多设备开关设置失败: ${JSON.stringify(err)}`);
    }
  }

  // 切换多设备开关
  onMultiDeviceToggle(enabled: boolean) {
    this.isMultiDeviceEnabled = enabled;
    this.saveMultiDeviceSetting(enabled);
  }

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
        // 有图片时：功能区域在顶部，下方显示滚动内容
        // 多设备开关（小卡片样式）
        Row() {
          Text($r('app.string.multi_device'))
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.isMultiDeviceEnabled })
            .selectedColor($r('sys.color.ohos_id_color_activated'))
            .onChange((isOn: boolean) => {
              this.onMultiDeviceToggle(isOn);
            })
        }
        .width('40%')
        .height(50)
        .padding({ left: 16, right: 16 })
        .borderRadius(16)
        .border({ width: 1, color: '#19000000' })
        .backgroundColor($r('sys.color.ohos_id_color_dialog_bg'))
        .shadow({ radius: 6, color: '#26000000', offsetX: 0, offsetY: 2 })
        .margin({ bottom: 10 })

        Row() {
          // 所有设备：根据开关状态决定显示哪种按钮
          if (this.isMultiDeviceEnabled) {
            // 开启多设备：显示跨设备协作菜单
            if (this.mainWindowInfo.widthBp === 'lg' || this.mainWindowInfo.widthBp === 'xl') {
              // 平板/PC设备
              Button($r('app.string.pick'))
                .type(ButtonType.Capsule)
                .fontColor(Color.White)
                .width('20%')
                .margin({ right: 10 })
                .height(50)
                .backgroundColor($r('sys.color.ohos_id_color_activated'))
                .bindMenu(this.MyTestMenu)
            } else {
              // 手机设备
              Button($r('app.string.pick'))
                .type(ButtonType.Capsule)
                .fontColor(Color.White)
                .width('20%')
                .margin({ right: 10 })
                .height(50)
                .backgroundColor($r('sys.color.ohos_id_color_activated'))
                .bindMenu(this.PhonePickMenu)
            }
          } else {
            // 关闭多设备：显示普通本地选择按钮
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
          Button('OCR')
            .type(ButtonType.Capsule)
            .fontColor(Color.White)
            .alignSelf(ItemAlign.Center)
            .width('20%')
            .height(50)
            .backgroundColor($r('sys.color.ohos_id_color_activated'))
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
          // 多设备开关（小卡片样式）
          Row() {
            Text($r('app.string.multi_device'))
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.isMultiDeviceEnabled })
              .selectedColor($r('sys.color.ohos_id_color_activated'))
              .onChange((isOn: boolean) => {
                this.onMultiDeviceToggle(isOn);
              })
          }
          .width('40%')
          .height(50)
          .padding({ left: 16, right: 16 })
          .borderRadius(16)
          .border({ width: 1, color: '#19000000' })
          .backgroundColor($r('sys.color.ohos_id_color_dialog_bg'))
          .shadow({ radius: 6, color: '#26000000', offsetX: 0, offsetY: 2 })
          .margin({ bottom: 10 })

          Row() {
            // 所有设备：根据开关状态决定显示哪种按钮
            if (this.isMultiDeviceEnabled) {
              // 开启多设备：显示跨设备协作菜单
              if (this.mainWindowInfo.widthBp === 'lg' || this.mainWindowInfo.widthBp === 'xl') {
                // 平板/PC设备
                Button($r('app.string.pick'))
                  .type(ButtonType.Capsule)
                  .fontColor(Color.White)
                  .width('20%')
                  .margin({ right: 10 })
                  .height(50)
                  .backgroundColor($r('sys.color.ohos_id_color_activated'))
                  .bindMenu(this.MyTestMenu)
              } else {
                // 手机设备
                Button($r('app.string.pick'))
                  .type(ButtonType.Capsule)
                  .fontColor(Color.White)
                  .width('20%')
                  .margin({ right: 10 })
                  .height(50)
                  .backgroundColor($r('sys.color.ohos_id_color_activated'))
                  .bindMenu(this.PhonePickMenu)
              }
            } else {
              // 关闭多设备：显示普通本地选择按钮
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
            Button('OCR')
              .type(ButtonType.Capsule)
              .fontColor(Color.White)
              .alignSelf(ItemAlign.Center)
              .width('20%')
              .height(50)
              .backgroundColor($r('sys.color.ohos_id_color_activated'))

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
