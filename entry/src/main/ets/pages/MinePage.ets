import { common, Want } from '@kit.AbilityKit';
import { BusinessError, deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { promptAction, window, AtomicServiceWeb, AtomicServiceWebController } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { bundleManager } from '@kit.AbilityKit';

@Observed
class SettingMenu {
  public uri?: string;
  public webUrl?: string; // 备用网页链接
  public id: string;
  public symbol: Resource;
  public text: Resource | string;

  constructor(id: string, symbol: Resource, text: Resource | string, uri?: string, webUrl?: string) {
    this.id = id;
    this.symbol = symbol;
    this.text = text;
    this.uri = uri;
    this.webUrl = webUrl;
  }
}

@Entry
@Component
export struct MinePage {
  private iconStr: ResourceStr = $r("app.media.CIcon");
  @State menuGroup: SettingMenu[] = [
    new SettingMenu('vipownsetting', $r('sys.symbol.person_badge_plus'), $r('app.string.invite_test')),
    new SettingMenu('mycollection', $r('sys.symbol.heart'), $r('app.string.mine3'),
      'bilibili://space/338142387', 'https://space.bilibili.com/338142387'),
    new SettingMenu('mylike', $r('sys.symbol.hand_thumbsup'), $r('app.string.mine4'),
      'snssdk1128://user/profile/618379012226540?refer=web', 'https://www.douyin.com/user/MS4wLjABAAAAxFrsP4LK-iS49UNXIoHz_dwT1JU3FRHrvrKLs7HigGg'),
    new SettingMenu('browsinghistory', $r('sys.symbol.clock'), $r('app.string.mine5'),
      'https://blog.hnyqwq.cn', 'https://blog.hnyqwq.cn')
  ];

  @StorageLink('isImmersiveStatusBar') isImmersiveStatusBar: boolean = false;
  @StorageLink('isAtomicServiceBarImmersive') isAtomicServiceBarImmersive: boolean = false;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @State isPcDevice: boolean = false; // 是否是PC/2in1设备
  @State versionInfo: string = ''; // 版本信息
  @State appName: string = ''; // 应用包名
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private preferencesStore: preferences.Preferences | null = null;

  private readonly inviteTestUrl: string = 'https://appgallery.huawei.com/apptest/52fRvA7p5Ow';
  private readonly blogUrl: string = 'https://blog.hnyqwq.cn';

  async aboutToAppear(): Promise<void> {
    await this.checkDeviceCapability();
    await this.loadVersionInfo();
  }

  @State showWebView: boolean = false;
  @State webViewUrl: string = '';
  @State webViewTitle: ResourceStr = '';
  @State webController: AtomicServiceWebController = new AtomicServiceWebController();
  // 使用AtomicServiceEnhancedWeb组件内嵌打开链接（元服务不支持startAbility打开外部链接）
  private openInWebView(url: string, title: ResourceStr): void {
    this.webViewUrl = url;
    this.webViewTitle = title;
    this.showWebView = true;
  }

  // 检测设备能力
  private async checkDeviceCapability(): Promise<void> {
    // 检查是否是PC/2in1设备（deviceType返回'2in1'字符串）
    this.isPcDevice = deviceInfo.deviceType === '2in1';
    console.info(`设备能力检测: isPcDevice=${this.isPcDevice}, deviceType=${deviceInfo.deviceType}`);
  }

  // 加载版本信息
  private async loadVersionInfo(): Promise<void> {
    try {
      const bundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      const versionName = bundleInfo.versionName;
      const versionCode = bundleInfo.versionCode;
      this.versionInfo = `${versionName} (${versionCode})`;
      this.appName = bundleInfo.name; // 获取应用包名
    } catch (error) {
      console.error('获取版本信息失败:', error);
    }
  }

  // 切换顶部状态栏沉浸化（不保存设置，每次启动需手动开启）
  private async toggleImmersiveStatusBar(): Promise<void> {
    // PC/2in1设备不支持
    if (this.isPcDevice) {
      promptAction.showToast({ message: $r('app.string.status_bar_not_supported_pc') });
      return;
    }

    const newValue = !this.isImmersiveStatusBar;
    this.isImmersiveStatusBar = newValue;
    // 不保存设置

    // 立即应用状态栏设置
    try {
      const win = await window.getLastWindow(this.context);
      if (newValue) {
        // 沉浸模式：隐藏状态栏
        await win.setWindowSystemBarEnable(['navigation']);
        console.info('Immersive status bar enabled');
      } else {
        // 正常模式：显示状态栏
        await win.setWindowSystemBarEnable(['status', 'navigation']);
        console.info('Immersive status bar disabled');
      }
    } catch (error) {
      console.error('Failed to apply status bar setting:', error);
    }

    promptAction.showToast({
      message: newValue ? $r('app.string.immersive_status_bar_enabled') : $r('app.string.immersive_status_bar_disabled')
    });
  }

  // 切换元服务胶囊沉浸（不保存设置，每次启动需手动开启）
  private toggleAtomicServiceBarImmersive(): void {
    this.isAtomicServiceBarImmersive = !this.isAtomicServiceBarImmersive;
    promptAction.showToast({
      message: this.isAtomicServiceBarImmersive ? $r('app.string.atomic_service_bar_immersive_enabled') : $r('app.string.atomic_service_bar_immersive_disabled')
    });
  }

  // 保存沉浸设置（通用方法）
  private async saveImmersiveSetting(key: string, value: boolean): Promise<void> {
    try {
      if (!this.preferencesStore) {
        this.preferencesStore = await preferences.getPreferences(this.context, 'immersive_settings');
      }
      await this.preferencesStore.put(key, value);
      await this.preferencesStore.flush();
      console.info(`${key}设置已保存:`, value);
    } catch (error) {
      console.error(`保存${key}设置失败:`, error);
    }
  }

  // 设置长按菜单
  @Builder
  MyMenu() {
    Menu() {
      MenuItem({ startIcon: this.iconStr, content: $r('app.string.minelongpress') })
        .onClick(() => {
          let want: Want = {
            "action": "ohos.want.action.viewData",
            "entities": ["entity.system.browsable"],
            uri: 'https://www.hnyqwq.cn/hvideo',
          }
          let context = getContext(this) as common.UIAbilityContext;
          context.startAbility(want)
          console.info(`MenuItem ability succeed`)
        })
    }
  }

  // 预览组件
  @Builder
  MyPreview() {
    Column() {
      Image($r('app.media.CIcon'))
        .width(200)
        .height(200)
    }
  }

  build() {
    Stack() {
      Scroll() {
      Column() {
        // 顶部用户信息区域
        Column() {
          Image($r('app.media.CIcon'))
            .width(70)
            .height(70)
            .borderRadius(35)
            .bindContextMenu(this.MyMenu, ResponseType.LongPress, {
              preview: this.MyPreview,
              previewAnimationOptions: {
                hoverScale: [1.0, 0.95]
              }
            })

          Text($r('app.string.appname'))
            .fontWeight(FontWeight.Bold)
            .fontSize(18)
            .fontColor($r('app.color.font_color_182431'))
            .margin({ top: 12 })

          Text(this.versionInfo)
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
            .margin({ top: 4 })
        }
        .width('100%')
        .padding({ top: (this.isImmersiveStatusBar ? 0 : px2vp(this.topRectHeight)) + (this.isAtomicServiceBarImmersive ? 0 : 50) + 10, bottom: 30 })

        // 菜单列表区域
        Column() {
          // 元服务胶囊沉浸开关
          Row() {
            Column() {
              Text($r('app.string.atomic_service_bar_immersive_title'))
                .fontSize(16)
                .fontColor($r('app.color.font_color_182431'))
              Text($r('app.string.atomic_service_bar_immersive_desc'))
                .fontSize(12)
                .fontColor($r('sys.color.font_secondary'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.isAtomicServiceBarImmersive })
              .selectedColor($r('sys.color.ohos_id_color_activated'))
              .onChange((isOn: boolean) => {
                this.toggleAtomicServiceBarImmersive();
              })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 12, bottom: 12 })
          .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.list_border_color') })
          .margin({ bottom: 12 })

          // 状态栏沉浸开关
          Row() {
            Column() {
              Text($r('app.string.immersive_status_bar_title'))
                .fontSize(16)
                .fontColor($r('app.color.font_color_182431'))
              Text($r('app.string.immersive_status_bar_desc'))
                .fontSize(12)
                .fontColor($r('sys.color.font_secondary'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.isPcDevice) {
              Text($r('app.string.status_bar_not_supported_pc'))
                .fontSize(12)
                .fontColor($r('sys.color.font_secondary'))
            } else {
              Toggle({ type: ToggleType.Switch, isOn: this.isImmersiveStatusBar })
                .selectedColor($r('sys.color.ohos_id_color_activated'))
                .onChange((isOn: boolean) => {
                  this.toggleImmersiveStatusBar();
                })
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 12, bottom: 12 })
          .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.list_border_color') })
          .margin({ bottom: 12 })

          List({ space: 0 }) {
            ForEach(this.menuGroup, (item: SettingMenu, index: number) => {
              ListItem() {
                Row() {
                  SymbolGlyph(item.symbol)
                    .fontSize(22)
                    .fontColor([$r('sys.color.icon_primary')])

                  if (item.id === 'vipownsetting') {
                    Column() {
                      Text($r('app.string.invite_test'))
                        .fontSize($r('sys.float.Subtitle_M'))
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('sys.color.font_primary'))
                        .margin({ left: $r('sys.float.padding_level8') })
                      Text(this.inviteTestUrl)
                        .fontSize($r('sys.float.Caption_S'))
                        .fontColor($r('sys.color.font_tertiary'))
                        .margin({ left: $r('sys.float.padding_level8'), top: 2 })
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                  } else if (item.id === 'browsinghistory') {
                    Column() {
                      Text($r('app.string.mine5'))
                        .fontSize($r('sys.float.Subtitle_M'))
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('sys.color.font_primary'))
                        .margin({ left: $r('sys.float.padding_level8') })
                      Text(this.blogUrl)
                        .fontSize($r('sys.float.Caption_S'))
                        .fontColor($r('sys.color.font_tertiary'))
                        .margin({ left: $r('sys.float.padding_level8'), top: 2 })
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                  } else {
                    Text(item.text)
                      .fontSize(16)
                      .fontColor($r('app.color.font_color_182431'))
                      .margin({ left: 16 })
                      .layoutWeight(1)
                  }

                  if (item.id !== 'vipownsetting' && item.id !== 'browsinghistory') {
                    Image($r('sys.media.ohos_ic_public_arrow_right'))
                      .width(16)
                      .height(16)
                      .fillColor($r('sys.color.icon_secondary'))
                  }
                }
                .width('100%')
                .height(56)
                .padding({ left: 20, right: 20 })
                .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
                .onClick(() => {
                    if (item.id === 'vipownsetting') {
                      this.copyLinkToClipboard(this.inviteTestUrl);
                      return;
                    }
                    if (item.id === 'browsinghistory') {
                      this.copyLinkToClipboard(this.blogUrl);
                      return;
                    }
                    if (item.uri) {
                      this.openWithFallback(item.uri, item.webUrl);
                    }
                  })
              }
            }, (item: SettingMenu) => item.id.toString())
          }
          .width('100%')
          .borderRadius(12)
          .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
          .clip(true)
          .border({ width: 1, color: $r('app.color.list_border_color') })
          .divider({
            strokeWidth: 0.5,
            color: $r('app.color.list_border_color'),
            startMargin: 58,
            endMargin: 20
          })
        }
        .width('92%')
        .margin({ top: 12 })

        // 底部协议信息区域
        Column() {
          Text() {
            Span($r('app.string.appysxy'))
              .onClick(() => {
                this.openInWebView('https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1973580013525556416', $r('app.string.appysxy'));
              })
              .fontColor(Color.Blue)
              .fontWeight(FontWeight.Regular)
              .fontSize($r('sys.float.Body_S'))
          }
          Row() {
            Text(this.appName)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .fontSize($r('sys.float.Body_S'))
              .margin({ right: $r('sys.float.padding_level2') })
            /*Text($r('app.string.copyright'))
              .fontColor($r('sys.color.font_secondary'))
              .fontWeight(FontWeight.Medium)
              .fontSize($r('sys.float.Body_S'))*/
          }
          Text() {
            Span('蜀ICP备2025142744号-10K')
              .onClick(() => {
                this.openInWebView('https://beian.miit.gov.cn', '蜀ICP备2025142744号-10K');
              })
              .fontColor(Color.Blue)
              .fontSize(12);
          }
        }
        .width('100%')
        .padding({ top: 30, bottom: 20 })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .padding({ bottom: px2vp(this.bottomRectHeight) })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ bottom: px2vp(this.bottomRectHeight) })
    .backgroundColor($r('sys.color.ohos_id_color_background'))
    .expandSafeArea([SafeAreaType.SYSTEM])

      // WebView覆盖层
      if (this.showWebView) {
        Column() {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(24)
              .fontColor([$r('sys.color.font_primary')])
              .margin({ left: 16 })
              .onClick(() => { this.showWebView = false; })
            Text(this.webViewTitle)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .margin({ left: 12 })
          }
          .width('100%')
          .padding({ top: px2vp(this.topRectHeight) + 50, bottom: 12, left: 0, right: 0 })
          .backgroundColor($r('sys.color.ohos_id_color_background'))
          .border({ width: { bottom: 0.5 }, color: $r('sys.color.ohos_id_color_list_separator') })

          AtomicServiceWeb({
            src: this.webViewUrl,
            controller: this.webController,
          })
            .width('100%')
            .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('sys.color.ohos_id_color_background'))
      }
    }
    .width('100%')
    .height('100%')
  }

  // 复制链接到剪贴板
  private copyLinkToClipboard(url: string): void {
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
    const systemPasteboard = pasteboard.getSystemPasteboard();
    systemPasteboard.setData(pasteData).then(() => {
      promptAction.showToast({ message: '链接已复制', duration: 1500 });
    }).catch((err: BusinessError) => {
      console.error('复制链接失败: ' + err.message);
    });
  }

  // 打开URL
  private openUrl(uri: string) {
    try {
      let want: Want = {
        "action": "ohos.want.action.viewData",
        "entities": ["entity.system.browsable"],
        uri: uri,
        "type": "text/plain"
      }
      let context = getContext(this) as common.UIAbilityContext;
      context.startAbility(want)
      console.info(`explicit start ability succeed`)
    } catch (error) {
      console.info(`explicit start ability failed`)
    }
  }

  // Deep Linking：优先尝试拉起App，失败则打开网页
  private openWithFallback(uri: string, webUrl?: string) {
    const context = getContext(this) as common.UIAbilityContext;
    
    // HTTP/HTTPS链接直接打开
    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      this.openUrl(uri);
      return;
    }
    
    // URL Scheme：检测是否可打开
    try {
      const canOpen: boolean = bundleManager.canOpenLink(uri);
      console.info(`canOpenLink(${uri}): ${canOpen}`);
      
      if (canOpen) {
        // 拉起目标App
        context.openLink(uri, { appLinkingOnly: false })
          .catch(() => {
            // 失败时打开网页
            if (webUrl) {
              this.openUrl(webUrl);
            }
          });
      } else {
        // 不能打开时使用网页
        if (webUrl) {
          this.openUrl(webUrl);
        }
      }
    } catch (error) {
      console.error(`openWithFallback error: ${error}`);
      // 异常时尝试网页
      if (webUrl) {
        this.openUrl(webUrl);
      }
    }
  }
}
