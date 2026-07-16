import { unifiedDataChannel, uniformTypeDescriptor } from '@kit.ArkData';
import { promptAction, SymbolGlyphModifier } from '@kit.ArkUI';
import window from '@ohos.window';
import { common } from '@kit.AbilityKit';
import { scanCore, scanBarcode } from '@kit.ScanKit';
// 导入默认界面需要的日志模块和错误码模块
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import Logger from '../utils/Logger';
import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';

//两个临时无需权限组件
import { pasteboard } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';

//分享相关
import { fileUri } from '@kit.CoreFileKit';
import request from '@ohos.request';
import router from '@ohos.router';
import { image } from '@kit.ImageKit';
import KnockShareGuideCard, { CardRes } from '../model/KnockShareGuideCard';
import { WindowInfo } from '../utils/WindowInfo';

interface myParams {
  uri: string
};

let logger = Logger.getLogger('[KnockShare]');
let context = getContext(this) as common.UIAbilityContext;
let filesDir = context.filesDir;

@Entry
@Component
  // 使用@Entry装饰器标记为入口组件，@Component表示自定义组件
export struct HomePage {
  @State orientationBeforeFullscreen: window.Orientation = window.Orientation.PORTRAIT; // 进入全屏前的方向
  @State curRate: PlaybackSpeed = PlaybackSpeed.Speed_Forward_1_00_X
  @State isShortcutKeyEnabled: boolean = false
  @StorageLink('networkVideoSrc') networkVideoSrc: string = '';
  @State isPlaying: boolean = true;
  @State picture: PixelMap | undefined = undefined;
  @StorageLink('sharepng') sharepng: string = 'https://app.hnyqwq.cn/png/YYTB.png'
  @State savefileUri:string = ' ';
  @State currentFitMode: ImageFit = ImageFit.Auto; // 当前填充模式
  @State isControls: boolean = true; // 控制栏显示状态
  @State handlePopup: boolean = false; // 气泡提示（Popup）
  @State enableShortcutKey: boolean = true; //设置组件支持快捷键响应。
  //碰一碰
  @State whiteStatus: boolean = false;
  @State isKnockShareSupported: boolean = false;
  @ObjectLink mainWindowInfo: WindowInfo;
  @StorageLink('isImmersiveTab') isImmersiveTab: boolean = false;
  @StorageLink('isImmersiveStatusBar') isImmersiveStatusBar: boolean = false;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  
  // 网页视频提取相关状态
  @State showVideoExtractor: boolean = false; // 是否显示视频提取面板
  @State extractorUrl: string = ''; // 输入的网页链接
  @StorageLink('extractedVideos') @Watch('onExtractedVideosChanged') extractedVideos: VideoLinkItem[] = []; // 提取的视频链接
  @State isExtracting: boolean = false; // 是否正在提取
  @State isFetchingSize: boolean = false; // 是否正在获取视频大小（防止Watch重入死循环）
  @State webViewVisible: boolean = false; // WebView是否可见
  @State webSrc: string = 'about:blank'; // WebView加载的URL
  @State loadProgress: number = 0; // WebView加载进度

  // 菜单图标
  @State sampleIconModifier: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.play_circle')).fontSize('20vp');
  @State scanIconModifier: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.qrcode')).fontSize('20vp');
  
  private controller: VideoController = new VideoController();
  private webController: webview.WebviewController = new webview.WebviewController();
  private webViewTimeoutId: number = 0;
  private currentExtractorUrl: string = '';
  // 多设备协作：接收视频
  private doInsertVideo(stateCode: number, bufferType: string, buffer: ArrayBuffer): void {
    if (stateCode != 0) {
      return;
    }
    if (bufferType == "general.video") {
      try {
        const uint8Buf = new Uint8Array(buffer);
        const bufferLength = uint8Buf.byteLength;
        console.info(`[HomePage] 跨设备视频回调: buffer大小=${bufferLength}`);

        // 尝试将buffer解析为文本（可能为文件URI）
        let textContent = '';
        try {
          const textDecoder = util.TextDecoder.create('utf-8');
          textContent = textDecoder.decodeToString(uint8Buf);
          console.info(`[HomePage] 跨设备视频buffer文本内容: ${textContent}`);
        } catch (e) {
          console.info('[HomePage] buffer非文本内容');
        }

        // 判断是URI还是二进制视频数据
        const isUri = textContent.startsWith('file://') || textContent.startsWith('content://') ||
          textContent.startsWith('http://') || textContent.startsWith('https://');

        if (isUri) {
          // 收到的是文件URI，直接设置播放源
          console.info(`[HomePage] 跨设备视频URI: ${textContent}`);
          this.networkVideoSrc = '';
          this.networkVideoSrc = textContent;
          this.controller.start();
          promptAction.showToast({ message: $r('app.string.video_received_playing') });
        } else if (bufferLength > 1024) {
          // 收到的是二进制视频数据，写入临时文件
          const videoPath = this.context.filesDir + '/collaboration_video.mp4';
          const file = fs.openSync(videoPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
          fs.writeSync(file.fd, uint8Buf.buffer, { offset: 0, length: bufferLength });
          fs.closeSync(file);

          const stat = fs.statSync(videoPath);
          console.info(`[HomePage] 跨设备视频已保存: ${videoPath}, 文件大小=${stat.size}`);

          if (stat.size === 0) {
            console.error('[HomePage] 视频文件大小为0，写入失败');
            promptAction.showToast({ message: $r('app.string.video_received_failed') });
            return;
          }

          this.networkVideoSrc = '';
          this.networkVideoSrc = 'file://' + videoPath;
          this.controller.start();
          promptAction.showToast({ message: $r('app.string.video_received_playing') });
        } else {
          // buffer太小，既不是URI也不是视频，记录原始数据便于调试
          console.error(`[HomePage] 跨设备视频buffer异常: 大小=${bufferLength}, 内容=${textContent}`);
          promptAction.showToast({ message: $r('app.string.video_received_failed') });
        }
      } catch (error) {
        console.error('[HomePage] 处理跨设备视频失败:', JSON.stringify(error));
        promptAction.showToast({ message: $r('app.string.video_received_failed') });
      }
    }
  }
  saveButtonOptions: SaveButtonOptions = {
    icon: SaveIconStyle.FULL_FILLED,
    /*text: SaveDescription.SAVE_IMAGE,
    buttonType: ButtonType.Capsule*/
  }
  @State myContext: Context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  @State myFileTypes: number = 0;
  @StorageLink('myFileName') myFileName: string = '';
  @State myFileSize: number = 0;
  @State myUris: string = (this.getUIContext().getRouter().getParams() as myParams)?.uri ?? ' ';
  @StorageLink('uri') uri: string = '';
  //mediaFileUri: MediaFileUri = new MediaFileUri();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  //华为系统分享
  /*private async share() {
    if (!this.networkVideoSrc) {
      promptAction.showToast({ message: $r('app.string.nopeng') });
      return;
    }

    const contextFaker: Context = getContext(this);
    const resourceMgr: resourceManager.ResourceManager = contextFaker.resourceManager;
    const fileData: Uint8Array = await resourceMgr.getMediaContent($r('app.media.CIcon'));

    let context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    let shareData: systemShare.SharedData = new systemShare.SharedData({
      utd: utd.UniformDataType.HYPERLINK,
      content: this.networkVideoSrc, // 使用输入框中的视频链接
      title: context.resourceManager.getStringSync($r('app.string.shareinfo').id),
      description: this.networkVideoSrc,
      thumbnail: fileData,
    });
    let controller: systemShare.ShareController = new systemShare.ShareController(shareData);
    controller.show(context, {
      previewMode: systemShare.SharePreviewMode.DEFAULT,
      selectionMode: systemShare.SelectionMode.SINGLE
    }).then(() => {
      logger.info('ShareController show success.');
      promptAction.showToast({ message: '分享成功: ' + this.networkVideoSrc });
    }).catch((error: BusinessError) => {
      logger.error(`ShareController show error. code: ${error.code}, message: ${error.message}`);
      promptAction.showToast({ message: '分享失败: ' + error.message });
    });
  }*/

  private async share() {
    let uiContext: UIContext = this.getUIContext();
    if (!this.networkVideoSrc) {
      promptAction.showToast({ message: $r('app.string.nopeng') });
      return;
    }
    let context: common.UIAbilityContext = uiContext.getHostContext() as common.UIAbilityContext;

    // 网络链接分享
    let contextFaker: Context = uiContext.getHostContext() as Context;
    // 缩略图路径
    let thumbnailPath = contextFaker.filesDir + '/CIcon.png';

    // 检查文件是否存在且大小大于0
    let needDownload = false;
    try {
      const stat = await fs.stat(thumbnailPath);
      if (stat.size === 0) {
        console.info('CIcon.png exists but empty, need redownload');
        needDownload = true;
      }
    } catch {
      console.info('CIcon.png not exists, need download');
      needDownload = true;
    }

      let imageSource: image.ImageSource = image.createImageSource(thumbnailPath);
      let imagePacker: image.ImagePacker = image.createImagePacker();
      let buffer: ArrayBuffer = await imagePacker.packToData(imageSource, {
        format: 'image/jpeg',
        quality: 30
      });

  }


  isValidUrl(url: string): boolean {
    const pattern = /^(https?:\/\/)?([\da-z.-]+)\.([a-z.]{2,6})([\/\w .-]*)*\/?$/;
    return pattern.test(url);
  }
  onPageHide(): void {//隔空传送
    let uiContext: UIContext = this.getUIContext();
    let context: Context = uiContext.getHostContext() as Context;
    context.eventHub.emit('onBackGround');
  }

  aboutToAppear(): void {
    console.info(`[HomePage] aboutToAppear: currentBreakpointForUI=${this.mainWindowInfo.widthBp}`);
    // 判断设备是否支持碰一碰分享：具备 HarmonyShare 能力且非大屏（lg/xl）
    this.isKnockShareSupported = canIUse('SystemCapability.Collaboration.HarmonyShare')
    let context = getContext(this);

    // 延迟设置，确保窗口已经完全创建
    this.initWindowTimer = setTimeout(() => {
      window.getLastWindow(this.context).then((win: window.Window) => {
        // 保持全屏布局模式（expandSafeArea需要窗口为全屏布局才能延伸到安全区）
        // win.setWindowLayoutFullScreen(false); // 已移除：由EntryAbility统一设置为true
        // 显示状态栏和导航栏
        win.setWindowSystemBarEnable(['status', 'navigation']);
      }).catch((err: Error) => {
        console.error('设置状态栏失败:', err);
      });
    }, 100);

    // 建议调整顺序确保实时参数优先
    const params = router.getParams() as Record<string, string>;
    if (params?.['videoUrl']) {
      this.networkVideoSrc = params['videoUrl'];
    }
    const sharedUrl = AppStorage.get<string>('sharedVideoUrl');
    if (sharedUrl && this.isValidUrl(sharedUrl)) {
      this.networkVideoSrc = sharedUrl;
      AppStorage.delete('sharedVideoUrl');
    }
    // 触发视频加载
    this.context.eventHub.on('urlUpdate', this.urlUpdateCallback)
  }

  aboutToDisappear(): void {
    logger.info('aboutToDisappear invoked.');
    let context = getContext(this);

    // 清理所有定时器
    clearTimeout(this.debounceTimer);
    clearTimeout(this.urlDebounceTimer);
    clearTimeout(this.initWindowTimer);

    // 清理事件监听
    context.eventHub.off('urlUpdate', this.urlUpdateCallback);
    context.eventHub.off('onBackGround');

    // 页面消失时恢复状态栏和导航栏的显示
    window.getLastWindow(this.context).then((win: window.Window) => {
      win.setWindowSystemBarEnable(['status', 'navigation']);
    }).catch((err: Error) => {
      console.error('恢复状态栏失败:', err);
    });
  }

  //碰一碰分享
  private getCardSwiperResources(): CardRes[] {
    // 使用响应式状态变量
    const bp = this.mainWindowInfo.widthBp;
    console.info(`HomePage getCardSwiperResources called: currentBreakpointForUI=${bp}`);
    // 如果bp未定义,返回默认的3张卡片
    if (!bp) {
      console.warn('HomePage getCardSwiperResources: currentBreakpointForUI is undefined, using default resources');
      return [
        {
          title: $r('app.string.phone_can_knock_share'),
          text: $r('app.string.knock_guide_phone_hos5'),
          urlPrefix: 'https://app.hnyqwq.cn/hvideo/knock/knock_share_guide_phone_',
          framesCount: 128,
          startDelay: 50,
          stopDelay: 500,
        },
        {
          title: $r('app.string.phone_to_pc_can_knock_share'),
          text: $r('app.string.knock_guide_phone_hos6'),
          urlPrefix: 'https://app.hnyqwq.cn/hvideo/knock/knock_share_guide_pc_',
          framesCount: 104,
          startDelay: 50,
          stopDelay: 50,
        },
        {
          title: $r('app.string.pc_to_phone_can_knock_share'),
          text: $r('app.string.knock_guide_pc_hos6'),
          urlPrefix: 'https://app.hnyqwq.cn/hvideo/knock/knock_share_guide_pc_pull_',
          framesCount: 150,
          startDelay: 500,
          stopDelay: 1000,
        },
      ];
    }
    if (bp === 'xl') {
      // PC设备（xl）：显示PC端卡片（2张）
      console.info('HomePage getCardSwiperResources: 返回PC端卡片（2张）');
      return [
        {
          title: $r('app.string.phone_to_pc_can_knock_share'),
          text: $r('app.string.knock_guide_phone_hos6'),
          urlPrefix: 'https://app.hnyqwq.cn/hvideo/knock/knock_share_guide_pc_',
          framesCount: 104,
          startDelay: 50,
          stopDelay: 50,
        },
        {
          title: $r('app.string.pc_to_phone_can_knock_share'),
          text: $r('app.string.knock_guide_pc_hos6'),
          urlPrefix: 'https://app.hnyqwq.cn/hvideo/knock/knock_share_guide_pc_pull_',
          framesCount: 150,
          startDelay: 500,
          stopDelay: 1000,
        },
      ];
    } else {
      // sm/md/lg/未定义：显示3张卡片
      console.info('HomePage getCardSwiperResources: 返回3张卡片');
      return [
        {
          title: $r('app.string.phone_can_knock_share'),
          text: $r('app.string.knock_guide_phone_hos5'),
          urlPrefix: 'https://app.hnyqwq.cn/hvideo/knock/knock_share_guide_phone_',
          framesCount: 128,
          startDelay: 50,
          stopDelay: 500,
        },
        {
          title: $r('app.string.phone_to_pc_can_knock_share'),
          text: $r('app.string.knock_guide_phone_hos6'),
          urlPrefix: 'https://app.hnyqwq.cn/hvideo/knock/knock_share_guide_pc_',
          framesCount: 104,
          startDelay: 50,
          stopDelay: 50,
        },
        {
          title: $r('app.string.pc_to_phone_can_knock_share'),
          text: $r('app.string.knock_guide_pc_hos6'),
          urlPrefix: 'https://app.hnyqwq.cn/hvideo/knock/knock_share_guide_pc_pull_',
          framesCount: 150,
          startDelay: 500,
          stopDelay: 1000,
        },
      ];
    }
  }

  // 获取是否显示卡片的标志：所有设备都渲染碰一碰引导卡片
  private shouldShowCards(): boolean {
    console.info(`HomePage shouldShowCards: currentBreakpointForUI=${this.mainWindowInfo.widthBp}`);
    return true;
  }
  private debounceTimer: number = 0
  private urlDebounceTimer: number = 0
  private initWindowTimer: number = 0
  private urlUpdateCallback = (url: string) => {
    this.networkVideoSrc = url
    this.controller.start()
  }

  private updateImageExtension() {
    // 根据URL更新图片扩展名
  }
  //本地
  async getFilenameByUriForMedia(myUris: string[]) {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/ViewMedia',
      params: {
        uris: myUris
      }
    }, router.RouterMode.Standard);
  }
  // Pull up the picker to select images/videos.
  async callFilePickerSelectImage(): Promise<void> {
    let array: string[];
    let PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    PhotoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE;
    PhotoSelectOptions.maxSelectNumber = 1;
    let mediaFlag = false;
    // Create a PhotoViewPicker object.
    let photoPicker = new photoAccessHelper.PhotoViewPicker();
    photoPicker.select(PhotoSelectOptions).then((PhotoSelectResult) => {
      JSON.stringify(PhotoSelectResult);
      if (PhotoSelectResult !== null && PhotoSelectResult !== undefined) {
        // Declare variable array, whose value is the array in PhotoSelectResult.
        array = PhotoSelectResult['photoUris'];
        array.forEach((value) => {
          this.uri = value;
          mediaFlag = true;
        })
        this.networkVideoSrc = '';
        this.networkVideoSrc = this.uri; // 明确取第一个元素
      }
      if (mediaFlag) {
        this.getFilenameByUriForMedia(array);
      }
    })
  }

  async getMediaNameByUri(myUri: string) {
    this.myFileName = (myUri.split('/').pop()) as string;
  }
  /*private async selectImage() {
    let uri = await this.openPhoto();
    if (uri === undefined) {
      hilog.error(0x0000, 'LOCAL', "Failed to get uri.");
      return;
    }
    this.networkVideoSrc=uri;
  }

  private openPhoto(): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      let photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      photoPicker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE,
        maxSelectNumber: 1
      }).then((res: photoAccessHelper.PhotoSelectResult) => {
        resolve(res.photoUris[0]);
      }).catch((err: BusinessError) => {
        hilog.error(0x0000, 'LOCAL', `Failed to get photo image uri. code：${err.code}，message：${err.message}`);
        reject('');
      })
    })
  }
  async  (myUris: string[]) {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/ViewMedia',
      params: {
        uris: myUris
      }
    }, router.RouterMode.Standard);
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
      createCollaborationServiceMenuItems([CollaborationServiceFilter.ALL], 1)//API20 VIDEO_PICKER
    }
  }*/

  // 跨设备协作菜单
  @Builder
  MultiDeviceMenu() {
    Menu() {
      MenuItem({
        startIcon: $r("app.media.CIcon"),
        content: $r('app.string.local_video'),
        builder: (): void => {
          this.callFilePickerSelectImage();
        }
      })
    }
  }

  build() {
    Stack() {
    Scroll() {
      Column() {
        // 顶部避让状态栏
        if (!this.isImmersiveStatusBar) {
          Column()
            .height(px2vp(this.topRectHeight))
        }
        // 视频播放区域
      Stack() {
        Video({
          src: this.networkVideoSrc,
          previewUri: '',
          currentProgressRate: this.curRate,
          controller: this.controller,
          posterOptions: {
            showFirstFrame: true,
            contentTransitionEffect: ContentTransitionEffect.OPACITY
          }
        })
          .muted(false)
          .controls(this.isControls && this.networkVideoSrc !== '')
          .autoPlay(true)
          .loop(true)
          .objectFit(this.currentFitMode)
          .width('100%')
          .height('100%')
          .onClick(() => {
            if (this.networkVideoSrc === '') return;
            this.isControls = !this.isControls;
            if (this.isControls) {
              promptAction.showToast({ message: $r('app.string.controlon') });
            } else {
              promptAction.showToast({ message: $r('app.string.controloff') });
            }
          })
          .enableShortcutKey(this.isShortcutKeyEnabled)
          .onStart(() => {
            console.info('onStart')
          })
          .onPause(() => {
            console.info('onPause')
          })
          .onFinish(() => {
            console.info('onFinish')
          })
          .onError(() => {
            console.info('onError')
          })
          .onStop(() => {
            console.info('onStop')
          })
          .onPrepared((e?: DurationObject) => {
            if (e != undefined) {
              console.info('onPrepared is ' + e.duration)
            }
          })
          .onSeeking((e?: TimeObject) => {
            if (e != undefined) {
              console.info('onSeeking is ' + e.time)
            }
          })
          .onSeeked((e?: TimeObject) => {
            if (e != undefined) {
              console.info('onSeeked is ' + e.time)
            }
          })
          .onUpdate((e?: TimeObject) => {
            if (e != undefined) {
              console.info('onUpdate is ' + e.time)
            }
          })
          .onFullscreenChange((e?: FullscreenObject) => {
            if (e != undefined) {
              console.info('onFullscreenChange is ' + e.fullscreen)
            }
          })
          .onPrepared(() => {
            this.controller.start();
          })
          .onDrop((e: DragEvent) => {
            let record = e.getData().getRecords()[0];
            if (record.getType() == uniformTypeDescriptor.UniformDataType.VIDEO) {
              let videoInfo = record as unifiedDataChannel.Video;
              this.networkVideoSrc = videoInfo.videoUri;
            }
          })

        // 无视频时的占位内容
        if (this.networkVideoSrc === '') {
          Column() {
            SymbolGlyph($r('sys.symbol.play_circle'))
              .fontSize(64)
              .fontColor([$r('sys.color.icon_secondary')])

            Text($r('app.string.no_video_placeholder'))
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .margin({ top: 12 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
          .borderRadius(0)
        }
      }
      .width('100%')
      .aspectRatio(16 / 9)
      .constraintSize({ maxWidth: 750, minWidth: 500 })
      // 视频输入区 - 卡片式设计
      Column() {
        // 链接输入行
        Row() {
          TextInput({
            placeholder: $r('app.string.linkinput'),
            text: this.networkVideoSrc
          })
            .type(InputType.URL)
            .layoutWeight(1)
            .height(44)
            .borderRadius(22)
            .backgroundColor($r('sys.color.ohos_id_color_background'))
  .expandSafeArea([SafeAreaType.SYSTEM])
            .border({ width: 1, color: $r('app.color.list_border_color') })
            .onChange((networkVideoSrc: string) => {
              this.networkVideoSrc = networkVideoSrc;
              AppStorage.set('networkVideoSrc', networkVideoSrc);
            })
            .cancelButton({ style: CancelButtonStyle.INPUT })

          // 更多操作按钮
          Button() {
            SymbolGlyph($r('sys.symbol.ellipsis_circle'))
              .fontSize(20)
              .fontColor([$r('sys.color.font_primary')])
          }
          .width(44)
          .height(44)
          .borderRadius(22)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .margin({ left: 8 })
          .bindMenu([
            {
              value: $r('app.string.sample_video'),
              symbolIcon: this.sampleIconModifier,
              action: () => {
                this.networkVideoSrc = 'https://consumer.huawei.com/content/dam/huawei-cbg-site/greate-china/cn/support/harmonyos-video/video/video-v28.mp4';
                AppStorage.set('networkVideoSrc', this.networkVideoSrc);
                promptAction.showToast({ message: $r('app.string.sample_video_loaded') });
              }
            },
            {
              value: $r('app.string.scan_input'),
              symbolIcon: this.scanIconModifier,
              action: async () => {
                try {
                  let options: scanBarcode.ScanOptions = {
                    scanTypes: [scanCore.ScanType.ALL],
                    enableMultiMode: true,
                    enableAlbum: true
                  };
                  scanBarcode.startScanForResult(getContext(this), options).then((result: scanBarcode.ScanResult) => {
                    const originalValue: string = result.originalValue;
                    if (originalValue && originalValue.trim() !== '') {
                      this.networkVideoSrc = originalValue.trim();
                      AppStorage.set('networkVideoSrc', originalValue.trim());
                    }
                    promptAction.showToast({ duration: 5000, message: $r('app.string.scan_success') });
                  }).catch((error: BusinessError) => {
                    hilog.error(0x0001, '[Scan]', `Failed: ${error.code}, ${error.message}`);
                    promptAction.showToast({ message: $r('app.string.scan_cancelled') });
                  });
                } catch (error) {
                  promptAction.showToast({ message: $r('app.string.scan_failed') });
                }
              }
            }
          ])
        }
        .width('100%')
        
        // 链接格式说明
        Text($r('app.string.link_format_hint'))
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .margin({ top: 8 })
          .width('100%')
      }
      .width('92%')
      .padding(16)
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
      .borderRadius(16)
      .border({ width: 1, color: $r('sys.color.ohos_id_color_list_separator') })
      .margin({ top: 12 })

      // 网页视频提取入口（可展开）
      Column() {
        // 标题栏
        Row() {
          SymbolGlyph($r('sys.symbol.link'))
            .fontSize(24)
            .fontColor([$r('sys.color.ohos_id_color_activated')])
          
          Column() {
            Text($r('app.string.web_video_extractor_title'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
            Text($r('app.string.web_video_extractor_desc'))
              .fontSize(11)
              .fontColor($r('sys.color.font_secondary'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 12 })
          .layoutWeight(1)

          SymbolGlyph(this.showVideoExtractor ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_primary')])
        }
        .width('100%')
        .padding(16)
        .onClick(() => {
          this.showVideoExtractor = !this.showVideoExtractor;
        })
        
        // 展开的提取面板
        if (this.showVideoExtractor) {
          Column() {
            // URL输入
            Row() {
              TextInput({ placeholder: $r('app.string.webpage_link_placeholder'), text: this.extractorUrl })
                .type(InputType.URL)
                .layoutWeight(1)
                .height(40)
                .borderRadius(20)
                .border({ width: 1, color: $r('app.color.list_border_color') })
                .onChange((value: string) => { this.extractorUrl = value; })
                .cancelButton({ style: CancelButtonStyle.INPUT })

              // 更多操作按钮
              Button() {
                SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                  .fontSize(16)
                  .fontColor([$r('sys.color.font_primary')])
              }
              .width(40)
              .height(40)
              .borderRadius(20)
              .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
              .margin({ left: 8 })
              .bindMenu([
                {
                  value: $r('app.string.sample_webpage'),
                  symbolIcon: this.sampleIconModifier,
                  action: () => {
                    this.extractorUrl = 'https://www.pexels.com/zh-cn/video/15212177/';
                    promptAction.showToast({ message: $r('app.string.sample_webpage_loaded') });
                  }
                },
                {
                  value: $r('app.string.scan_input'),
                  symbolIcon: this.scanIconModifier,
                  action: async () => {
                    try {
                      let options: scanBarcode.ScanOptions = {
                        scanTypes: [scanCore.ScanType.ALL],
                        enableMultiMode: true,
                        enableAlbum: true
                      };
                      scanBarcode.startScanForResult(getContext(this), options).then((result: scanBarcode.ScanResult) => {
                        const originalValue: string = result.originalValue;
                        if (originalValue && originalValue.trim() !== '') {
                          this.extractorUrl = originalValue.trim();
                        }
                        promptAction.showToast({ duration: 5000, message: $r('app.string.scan_success') });
                      }).catch((error: BusinessError) => {
                        hilog.error(0x0001, '[Scan]', `Failed: ${error.code}, ${error.message}`);
                        promptAction.showToast({ message: $r('app.string.scan_cancelled') });
                      });
                    } catch (error) {
                      promptAction.showToast({ message: $r('app.string.scan_failed') });
                    }
                  }
                }
              ])

              Button(this.isExtracting ? $r('app.string.extracting') : $r('app.string.extract'))
                .height(40)
                .borderRadius(20)
                .margin({ left: 8 })
                .backgroundColor($r('sys.color.ohos_id_color_activated'))
                .fontColor(Color.White)
                .enabled(!this.isExtracting)
                .onClick(() => this.startExtract())
            }
            .width('100%')
            
            // 提取结果
            if (this.extractedVideos.length > 0) {
              Text($r('app.string.found_videos_sorting', this.extractedVideos.length))
                .fontSize(12)
                .fontColor($r('sys.color.font_primary'))
                .margin({ top: 12 })
              
              List() {
                ForEach(this.extractedVideos, (item: VideoLinkItem, index: number) => {
                  ListItem() {
                    Column() {
                      // 第一行：格式标签 + 类型 + 大小
                      Row() {
                        Text(item.format.toUpperCase())
                          .fontSize(10)
                          .fontColor(Color.White)
                          .backgroundColor($r('sys.color.ohos_id_color_activated'))
                          .borderRadius(4)
                          .padding({ left: 6, right: 6, top: 2, bottom: 2 })

                        Text(item.type)
                          .fontSize(11)
                          .fontColor($r('sys.color.font_secondary'))
                          .margin({ left: 8 })
                        
                        Blank()
                        
                        // 视频大小 - 突出显示
                        Text(item.sizeText || $r('app.string.fetching'))
                          .fontSize(13)
                          .fontColor($r('sys.color.font_primary'))
                          .fontWeight(FontWeight.Bold)
                      }
                      .width('100%')

                      // 第二行：URL
                      Text(item.url)
                        .fontSize(11)
                        .fontColor($r('sys.color.font_secondary'))
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .margin({ top: 6 })
                        .width('100%')
                      
                      // 第三行：操作按钮
                      Row() {
                        Button($r('app.string.play_btn_short'))
                          .fontSize(11)
                          .height(28)
                          .borderRadius(14)
                          .fontColor(Color.White)
                          .backgroundColor($r('sys.color.ohos_id_color_activated'))
                          .onClick(() => this.playExtractedVideo(item.url))

                        Button($r('app.string.copy_btn'))
                          .fontSize(11)
                          .height(28)
                          .borderRadius(14)
                          .fontColor($r('sys.color.font_primary'))
                          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
                          .margin({ left: 8 })
                          .onClick(() => this.copyExtractedUrl(item.url))
                      }
                      .margin({ top: 8 })
                      .justifyContent(FlexAlign.End)
                    }
                    .width('100%')
                    .padding(12)
                    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
                    .borderRadius(10)
                    .border({
                      width: index === 0 ? 1.5 : 1,
                      color: index === 0 ? $r('sys.color.ohos_id_color_warning') : $r('sys.color.ohos_id_color_list_separator')
                    })
                    .margin({ bottom: 10 })
                  }
                }, (item: VideoLinkItem) => item.url + item.size.toString())
              }
              .width('100%')
              .height(180)
              .margin({ top: 8 })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 })
        }
      }
      .width('92%')
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
      .borderRadius(16)
      .border({ width: 1, color: $r('sys.color.ohos_id_color_list_separator') })
      .margin({ top: 12 })

      // 快捷操作区 - 网格布局
      Grid() {
        // 本地选择 + 多设备
        GridItem() {
          Flex({
            direction: (this.mainWindowInfo.widthBp === 'lg' || this.mainWindowInfo.widthBp === 'xl') ?
              FlexDirection.Row : FlexDirection.Column,
            alignItems: ItemAlign.Center,
            justifyContent: FlexAlign.Center
          }) {
            // 本地选择
            Flex({
              direction: (this.mainWindowInfo.widthBp === 'lg' || this.mainWindowInfo.widthBp === 'xl') ?
                FlexDirection.Column : FlexDirection.Row,
              alignItems: ItemAlign.Center,
              justifyContent: FlexAlign.Center
            }) {
              SymbolGlyph($r('sys.symbol.folder'))
                .fontSize(22)
                .fontColor([$r('sys.color.ohos_id_color_activated')])
              Text($r('app.string.local_video'))
                .fontSize(12)
                .fontColor($r('sys.color.font_primary'))
                .margin((this.mainWindowInfo.widthBp === 'lg' || this.mainWindowInfo.widthBp === 'xl') ?
                  { top: 4 } : { left: 4 })
            }
            .layoutWeight(1)
            .onClick(() => this.callFilePickerSelectImage())

            // 分割线：平板竖线，手机横线
            Divider()
              .vertical(this.mainWindowInfo.widthBp === 'lg' || this.mainWindowInfo.widthBp === 'xl')
              .height((this.mainWindowInfo.widthBp === 'lg' || this.mainWindowInfo.widthBp === 'xl') ? '60%' : undefined)
              .width((this.mainWindowInfo.widthBp === 'lg' || this.mainWindowInfo.widthBp === 'xl') ? undefined : '70%')
              .color($r('sys.color.ohos_id_color_list_separator'))
              .margin((this.mainWindowInfo.widthBp === 'lg' || this.mainWindowInfo.widthBp === 'xl') ?
                undefined : { top: 4, bottom: 4 })

            // 多设备协作
            Flex({
              direction: (this.mainWindowInfo.widthBp === 'lg' || this.mainWindowInfo.widthBp === 'xl') ?
                FlexDirection.Column : FlexDirection.Row,
              alignItems: ItemAlign.Center,
              justifyContent: FlexAlign.Center
            }) {
              SymbolGlyph($r('sys.symbol.folder_badge_eye'))
                .fontSize(22)
                .fontColor([$r('sys.color.ohos_id_color_activated')])
              Text($r('app.string.multi_device'))
                .fontSize(12)
                .fontColor($r('sys.color.font_primary'))
                .margin((this.mainWindowInfo.widthBp === 'lg' || this.mainWindowInfo.widthBp === 'xl') ?
                  { top: 4 } : { left: 4 })
            }
            .layoutWeight(1)
            .bindMenu(this.MultiDeviceMenu)
          }
          .width('100%')
          .height('100%')
          .borderRadius(12)
          .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
          .border({ width: 1, color: $r('sys.color.ohos_id_color_list_separator') })
        }

        // 播放/暂停
        GridItem() {
          Column() {
            SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause') : $r('sys.symbol.play'))
              .fontSize(28)
              .fontColor([$r('sys.color.ohos_id_color_warning')])
            Text(this.isPlaying ? $r('app.string.pause') : $r('app.string.play_btn'))
              .fontSize(12)
              .fontColor($r('sys.color.font_primary'))
              .margin({ top: 6 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .borderRadius(12)
          .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
          .border({ width: 1, color: $r('sys.color.ohos_id_color_list_separator') })
          .onClick(() => {
            if (this.isPlaying) {
              this.controller.pause();
            } else {
              this.controller.start();
            }
            this.isPlaying = !this.isPlaying;
          })
        }

        // 分享
        GridItem() {
          Column() {
            SymbolGlyph($r('sys.symbol.share'))
              .fontSize(28)
              .fontColor([$r('sys.color.ohos_id_color_activated')])
            Text($r('app.string.share_btn'))
              .fontSize(12)
              .fontColor($r('sys.color.font_primary'))
              .margin({ top: 6 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .borderRadius(12)
          .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
          .border({ width: 1, color: $r('sys.color.ohos_id_color_list_separator') })
          .onClick(() => this.share())
        }

        // 横屏
        GridItem() {
          Column() {
            SymbolGlyph($r('sys.symbol.rectangle_portrait_rotate'))
              .fontSize(28)
              .fontColor([$r('sys.color.ohos_id_color_activated')])
            Text($r('app.string.landscape_btn'))
              .fontSize(12)
              .fontColor($r('sys.color.font_primary'))
              .margin({ top: 6 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .borderRadius(12)
          .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
          .border({ width: 1, color: $r('sys.color.ohos_id_color_list_separator') })
          .onClick(() => {
            window.getLastWindow(this.context).then((win: window.Window) => {
              const cur = win.getPreferredOrientation();
              if (cur === window.Orientation.PORTRAIT || cur === window.Orientation.PORTRAIT_INVERTED) {
                this.orientationBeforeFullscreen = cur;
                win.setPreferredOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE);
                AppStorage.setOrCreate('isLandscape', true);
              } else {
                // 当前横屏，切回竖屏
                win.setPreferredOrientation(this.orientationBeforeFullscreen);
                AppStorage.setOrCreate('isLandscape', false);
              }
            }).catch(() => {});
          })
        }

        // 倍速
        GridItem() {
          Column() {
            SymbolGlyph($r('sys.symbol.timer'))
              .fontSize(28)
              .fontColor([$r('sys.color.ohos_id_color_warning')])
            Text($r('app.string.speedtitle'))
              .fontSize(12)
              .fontColor($r('sys.color.font_primary'))
              .margin({ top: 6 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .borderRadius(12)
          .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
          .border({ width: 1, color: $r('sys.color.ohos_id_color_list_separator') })
          .bindMenu([
            { value: $r('app.string.0125xspeed'), action: () => { this.curRate = PlaybackSpeed.SPEED_FORWARD_0_125_X; promptAction.showToast({ message: $r('app.string.0125xspeedyes') }); }},
            { value: $r('app.string.025xspeed'), action: () => { this.curRate = PlaybackSpeed.SPEED_FORWARD_0_25_X; promptAction.showToast({ message: $r('app.string.025xspeedyes') }); }},
            { value: $r('app.string.05xspeed'), action: () => { this.curRate = PlaybackSpeed.SPEED_FORWARD_0_50_X; promptAction.showToast({ message: $r('app.string.05xspeedyes') }); }},
            { value: $r('app.string.075xspeed'), action: () => { this.curRate = PlaybackSpeed.Speed_Forward_0_75_X; promptAction.showToast({ message: $r('app.string.075xspeedyes') }); }},
            { value: $r('app.string.1xspeed'), action: () => { this.curRate = PlaybackSpeed.Speed_Forward_1_00_X; promptAction.showToast({ message: $r('app.string.1xspeedyes') }); }},
            { value: $r('app.string.125xspeed'), action: () => { this.curRate = PlaybackSpeed.Speed_Forward_1_25_X; promptAction.showToast({ message: $r('app.string.125xspeedyes') }); }},
            { value: $r('app.string.15xspeed'), action: () => { this.curRate = PlaybackSpeed.SPEED_FORWARD_1_50_X; promptAction.showToast({ message: $r('app.string.15xspeedyes') }); }},
            { value: $r('app.string.175xspeed'), action: () => { this.curRate = PlaybackSpeed.Speed_Forward_1_75_X; promptAction.showToast({ message: $r('app.string.175xspeedyes') }); }},
            { value: $r('app.string.2xspeed'), action: () => { this.curRate = PlaybackSpeed.Speed_Forward_2_00_X; promptAction.showToast({ message: $r('app.string.2xspeedyes') }); }},
            { value: $r('app.string.3xspeed'), action: () => { this.curRate = PlaybackSpeed.SPEED_FORWARD_3_00_X; promptAction.showToast({ message: $r('app.string.3xspeedyes') }); }},
          ])
        }
        
        // 填充模式
        GridItem() {
          Column() {
            SymbolGlyph($r('sys.symbol.rectangle'))
              .fontSize(28)
              .fontColor([$r('sys.color.ohos_id_color_activated')])
            Text($r('app.string.fill_mode'))
              .fontSize(12)
              .fontColor($r('sys.color.font_primary'))
              .margin({ top: 6 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .borderRadius(12)
          .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
          .border({ width: 1, color: $r('sys.color.ohos_id_color_list_separator') })
          .bindMenu([
            { value: $r('app.string.Cover'), action: () => { this.currentFitMode = ImageFit.Cover; promptAction.showToast({ message: $r('app.string.Coveryes') }); }},
            { value: $r('app.string.Auto'), action: () => { this.currentFitMode = ImageFit.Auto; promptAction.showToast({ message: $r('app.string.Autoyes') }); }},
            { value: $r('app.string.Fill'), action: () => { this.currentFitMode = ImageFit.Fill; promptAction.showToast({ message: $r('app.string.Fillyes') }); }},
            { value: $r('app.string.Contain'), action: () => { this.currentFitMode = ImageFit.Contain; promptAction.showToast({ message: $r('app.string.Containyes') }); }},
          ])
        }
      }
      .columnsTemplate('1fr 1fr 1fr')
      .rowsTemplate('1fr 1fr')
      .columnsGap(12)
      .rowsGap(12)
      .width('92%')
      .height(180)
      .margin({ top: 12 })

      // 碰一碰提示卡片区域
      Column() {
        Text($r('app.string.nowplaying'))
        Text(this.networkVideoSrc)
          .padding({ top: 10 , bottom : 10 , left : 10 , right : 10 })
          .copyOption(CopyOptions.LocalDevice)
          .textAlign(TextAlign.Center)//.margin({ right: 10 })
          .width('100%')


        //碰一碰提示
        Text(deviceInfo.deviceType === 'tablet' ?
          $r('app.string.large_device_hint') : $r('app.string.nowplayingon'))
          .padding({ top: 10 , left: 24, right: 24 })
          .maxLines(5)
          .fontSize(11)
          .maxFontScale(1.75)
          .width('100%')
          .constraintSize({ minHeight: 16 })
          .fontColor($r('app.color.font_secondary'))
          .fontFamily('HarmonyHeiTi')
          .textAlign(TextAlign.Center)
        if (this.shouldShowCards()) {
          KnockShareGuideCard({
            cardSwiperResources: this.getCardSwiperResources(),
            isKnockShareSupported: this.isKnockShareSupported
          })
            .padding({ top: 2 })
        }

        /*Text(this.myFileName)
          .focusable(true)
          .focusOnTouch(true)
          .fontFamily('HarmonyHeiTi-Bold')
          .textAlign(TextAlign.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('Size: ' + JSON.stringify(this.myFileSize) + 'B')
          .focusable(true)
          .focusOnTouch(true)
          .fontFamily('HarmonyHeiTi')
          .textAlign(TextAlign.Start)*/
      }
      .width('90%')  // 控制内容区域宽度
      .alignItems(HorizontalAlign.Center) // 内容水平居中
      .margin({ top: 10 })
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .padding({ bottom: px2vp(this.bottomRectHeight) + (this.isImmersiveTab ? 84 : 0) })
  }
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Auto)
  .edgeEffect(EdgeEffect.Spring)
  .align(Alignment.Top)
  .backgroundColor($r('sys.color.ohos_id_color_background'))
  .expandSafeArea([SafeAreaType.SYSTEM])
  
  // WebView加载层（覆盖在主内容之上）
  if (this.webViewVisible) {
    Column() {
      Row() {
        Text($r('app.string.loading_progress', this.loadProgress))
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        Button($r('app.string.extract_video_btn'))
          .fontSize(12)
          .height(32)
          .margin({ right: 8 })
          .backgroundColor($r('sys.color.ohos_id_color_activated'))
          .onClick(() => this.getHtmlFromWebView())
        Button($r('app.string.close_btn'))
          .fontSize(12)
          .height(32)
          .onClick(() => {
            this.clearWebViewTimeout();
            this.webViewVisible = false;
            this.isExtracting = false;
          })
      }
      .width('100%')
      .padding(8)
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
      
      Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
        .width('100%')
        .color($r('sys.color.ohos_id_color_activated'))
      
      Text($r('app.string.wait_for_page_load'))
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
        .margin({ top: 2 , bottom: 2 })
      
      Web({ src: this.webSrc, controller: this.webController })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .mixedMode(MixedMode.All)
        .onPageEnd(() => {
          this.loadProgress = 100;
          promptAction.showToast({ message: $r('app.string.page_load_complete') });
        })
        .onProgressChange((event) => {
          if (event?.newProgress !== undefined) this.loadProgress = event.newProgress;
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_background'))
  .expandSafeArea([SafeAreaType.SYSTEM])
  }
  }
  }

  private isNoListening() {
    return !this.whiteStatus;
  }

  // ============ 网页视频提取相关方法 ============
  private readonly videoExtensions: string[] = [
    '.mp4', '.webm', '.mov', '.mkv', '.avi', '.flv', '.wmv', '.m4v', '.3gp', '.ogv', '.ts', '.m3u8'
  ];

  private parseBaseUrl(baseUrl: string): BaseUrlInfo {
    let protocol = 'https:';
    let origin = '';
    let basePath = '';
    if (baseUrl.startsWith('https://')) protocol = 'https:';
    else if (baseUrl.startsWith('http://')) protocol = 'http:';
    let temp = baseUrl.replace(/^https?:\/\//, '');
    const slashIndex = temp.indexOf('/');
    if (slashIndex > 0) {
      origin = protocol + '//' + temp.substring(0, slashIndex);
      basePath = temp.substring(slashIndex);
    } else {
      origin = protocol + '//' + temp;
      basePath = '/';
    }
    const result = new BaseUrlInfo();
    result.protocol = protocol;
    result.origin = origin;
    result.basePath = basePath;
    return result;
  }

  private toAbsoluteUrl(url: string, baseUrl: string): string {
    if (!url) return '';
    url = url.trim().replace(/[\\'"\s]+$/g, '');
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    const parsed = this.parseBaseUrl(baseUrl);
    if (url.startsWith('//')) return parsed.protocol + url;
    if (url.startsWith('/')) return parsed.origin + url;
    const lastSlashIndex = parsed.basePath.lastIndexOf('/');
    if (lastSlashIndex > 0) return parsed.origin + parsed.basePath.substring(0, lastSlashIndex + 1) + url;
    return parsed.origin + '/' + url;
  }

  private execRegex(regex: RegExp, text: string): string[][] {
    const results: string[][] = [];
    const globalRegex = new RegExp(regex.source, regex.flags);
    let match: RegExpExecArray | null = globalRegex.exec(text);
    while (match !== null) {
      const arr: string[] = [];
      for (let i = 0; i < match.length; i++) arr.push(match[i]);
      results.push(arr);
      match = globalRegex.exec(text);
    }
    return results;
  }

  private extractVideoLinks(html: string, baseUrl: string): VideoLinkItem[] {
    const links: VideoLinkItem[] = [];
    const addedUrls = new Set<string>();
    const addLink = (url: string, type: string): void => {
      const absoluteUrl = this.toAbsoluteUrl(url, baseUrl);
      if (!absoluteUrl || addedUrls.has(absoluteUrl)) return;
      const lowerUrl = absoluteUrl.toLowerCase();
      let format = 'unknown';
      for (const ext of this.videoExtensions) {
        if (lowerUrl.includes(ext)) { format = ext.replace('.', ''); break; }
      }
      addedUrls.add(absoluteUrl);
      const linkItem = new VideoLinkItem();
      linkItem.url = absoluteUrl;
      linkItem.type = type;
      linkItem.format = format;
      linkItem.size = 0;
      linkItem.sizeText = '';
      links.push(linkItem);
    };
    // 各种匹配模式
    const patterns: RegexPattern[] = [];
    const p1 = new RegexPattern();
    p1.regex = /<video[^>]+src=["']([^"']+)["']/gi;
    p1.type = 'video tag';
    patterns.push(p1);
    const p2 = new RegexPattern();
    p2.regex = /<source[^>]+src=["']([^"']+)["']/gi;
    p2.type = 'source tag';
    patterns.push(p2);
    const p3 = new RegexPattern();
    p3.regex = /["']((https?:)?\/\/[^"']+\.(?:mp4|webm|mov|mkv|avi|flv|m3u8|ts)(\?[^"']*)?)["']/gi;
    p3.type = 'JS/JSON';
    patterns.push(p3);
    const p4 = new RegexPattern();
    p4.regex = /data-(?:src|source|video)=["']([^"']+)["']/gi;
    p4.type = 'data attr';
    patterns.push(p4);
    const p5 = new RegexPattern();
    p5.regex = /["'](?:video_url|videoUrl|video_src|file_url|url)["']\s*:\s*["']([^"']+)["']/gi;
    p5.type = 'JSON field';
    patterns.push(p5);
    const p6 = new RegexPattern();
    p6.regex = /(https?:\/\/[^\s"'<>]+\.(?:mp4|webm|mov|mkv|avi|flv|m3u8|ts)(?:\?[^\s"'<>]*)?)/gi;
    p6.type = 'Raw URL';
    patterns.push(p6);
    for (const p of patterns) {
      const matches = this.execRegex(p.regex, html);
      for (const match of matches) if (match.length > 1) addLink(match[1], p.type);
    }
    // 视频托管域名
    const hostMatches = this.execRegex(/["']((https?:)?\/\/[^"']*(?:videos\.pexels|player\.vimeo|\.cloudfront\.net)[^"']*)["']/gi, html);
    for (const match of hostMatches) {
      if (match.length > 1) {
        const url = match[1];
        if (url.includes('.mp4') || url.includes('.webm') || url.includes('.m3u8') || url.includes('video')) {
          addLink(url, 'Video Host');
        }
      }
    }
    return links;
  }

  // 格式化文件大小
  private formatSize(bytes: number): string {
    if (bytes <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB'];
    let unitIndex = 0;
    let size = bytes;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return `${size.toFixed(unitIndex > 0 ? 1 : 0)} ${units[unitIndex]}`;
  }

  // 获取单个视频大小
  private async getVideoSize(url: string): Promise<number> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.HEAD,
        connectTimeout: 10000,
        readTimeout: 10000,
        header: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36'
        }
      });
      const headers = response.header as Record<string, string>;
      const contentLength = headers['content-length'];
      if (contentLength) {
        const size = parseInt(contentLength, 10);
        return isNaN(size) ? 0 : size;
      }
      return 0;
    } catch {
      return 0;
    } finally {
      httpRequest.destroy();
    }
  }

  // 从VideoExtractorPage传来视频链接时自动获取大小并排序
  private onExtractedVideosChanged(): void {
    if (this.extractedVideos.length === 0) {
      this.isFetchingSize = false; // 清空时重置标志，允许下次提取再次获取
      return;
    }
    // 防止重入：fetchVideoSizesAndSort 末尾的赋值会再次触发本回调
    if (this.isFetchingSize) return;
    // 如果视频大小都为0，说明是从提取页传来的，需要获取大小
    const needsFetchSize = this.extractedVideos.every(v => v.size === 0);
    if (needsFetchSize) {
      this.isFetchingSize = true;
      promptAction.showToast({ message: $r('app.string.found_videos_fetching_size', this.extractedVideos.length) });
      this.fetchVideoSizesAndSort().then(() => {
        this.isFetchingSize = false;
        promptAction.showToast({ message: $r('app.string.videos_sorted', this.extractedVideos.length) });
      }).catch(() => {
        this.isFetchingSize = false;
      });
    }
  }

  // 批量获取视频大小并排序
  private async fetchVideoSizesAndSort(): Promise<void> {
    if (this.extractedVideos.length === 0) return;
    
    // 并发获取所有视频大小
    const sizePromises = this.extractedVideos.map(async (video) => {
      const size = await this.getVideoSize(video.url);
      const result = new VideoLinkItem();
      result.url = video.url;
      result.type = video.type;
      result.format = video.format;
      result.size = size;
      result.sizeText = this.formatSize(size);
      return result;
    });
    
    const videosWithSize = await Promise.all(sizePromises);
    
    // 按大小降序排列
    videosWithSize.sort((a, b) => b.size - a.size);
    
    // 创建新数组触发UI更新
    const sortedVideos: VideoLinkItem[] = [];
    for (const video of videosWithSize) {
      sortedVideos.push(video);
    }
    this.extractedVideos = sortedVideos;
  }

  private clearWebViewTimeout(): void {
    if (this.webViewTimeoutId) {
      clearTimeout(this.webViewTimeoutId);
      this.webViewTimeoutId = 0;
    }
  }

  private async extractWithWebView(url: string): Promise<void> {
    this.currentExtractorUrl = url;
    this.loadProgress = 0;
    this.webSrc = url;
    this.webViewTimeoutId = setTimeout(() => {
      if (this.webViewVisible && this.loadProgress < 100) {
        this.clearWebViewTimeout();
        this.webViewVisible = false;
        this.isExtracting = false;
        promptAction.showToast({ message: $r('app.string.webpage_load_timeout') });
      }
    }, 60000);
    this.webViewVisible = true;
    promptAction.showToast({ message: $r('app.string.wait_for_page_load'), duration: 6000 });
  }

  private getHtmlFromWebView(): void {
    this.clearWebViewTimeout();
    this.webController.runJavaScript('document.documentElement.outerHTML').then(async (html: string) => {
      this.extractedVideos = this.extractVideoLinks(html, this.currentExtractorUrl);
      this.webViewVisible = false;
      this.isExtracting = false;
      if (this.extractedVideos.length === 0) {
        promptAction.showToast({ message: $r('app.string.no_video_found') });
      } else {
        promptAction.showToast({ message: $r('app.string.found_videos_fetching_size', this.extractedVideos.length) });
        // 异步获取视频大小并排序
        await this.fetchVideoSizesAndSort();
        promptAction.showToast({ message: $r('app.string.videos_sorted', this.extractedVideos.length) });
      }
    }).catch((err: BusinessError) => {
      this.webViewVisible = false;
      this.isExtracting = false;
      promptAction.showToast({ message: $r('app.string.extract_failed', err.message) });
    });
  }

  private async startExtract(): Promise<void> {
    if (!this.extractorUrl.trim()) {
      promptAction.showToast({ message: $r('app.string.enter_webpage_link') });
      return;
    }
    let url = this.extractorUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'https://' + url;
    if (!/^(https?:\/\/)?[\w.-]+\.[a-z]{2,}(:\d+)?(\/.*)?$/i.test(url)) {
      promptAction.showToast({ message: $r('app.string.enter_valid_webpage_link') });
      return;
    }
    // 跳转到 VideoExtractorPage 进行视频提取
    router.pushUrl({
      url: 'pages/VideoExtractorPage',
      params: { initialUrl: url }
    }, router.RouterMode.Standard);
  }

  private playExtractedVideo(url: string): void {
    this.networkVideoSrc = url;
    // 不收起面板，保持列表可见
    promptAction.showToast({ message: $r('app.string.video_link_set_loading'), duration: 6000 });
    this.controller.start();
  }

  private copyExtractedUrl(url: string): void {
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
    pasteboard.getSystemPasteboard().setData(pasteData);
    promptAction.showToast({ message: $r('app.string.link_copied') });
  }
}


interface DurationObject {
  duration: number;
}

interface TimeObject {
  time: number;
}

interface FullscreenObject {
  fullscreen: boolean;
}

// 视频提取相关接口
class VideoLinkItem {
  url: string = '';
  type: string = '';
  format: string = '';
  size: number = 0; // 视频大小（字节）
  sizeText: string = ''; // 可读的大小文本
}

class BaseUrlInfo {
  protocol: string = '';
  origin: string = '';
  basePath: string = '';
}

class RegexPattern {
  regex: RegExp = /()/;
  type: string = '';
}