import { createDbInsertData } from '../formcommon/DbIndex';
import { actionCreate, actionNewWant, actionWindowStageCreate } from '../formcommon/formsetting/FormAction';
import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';
import { url } from '@kit.ArkTS';
import { promptAction } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { WindowUtil } from '../utils/WindowUtil';

const TAG: string = 'EntryAbility';
const DOMAIN_NUMBER: number = 0xFF00;

export default class EntryAbility extends UIAbility {
  private selectPage: string = '';
  private currentWindowStage: window.WindowStage | null = null;
  storage: LocalStorage = new LocalStorage();
  private want: Want | undefined = undefined;
  private launchParam: AbilityConstant.LaunchParam | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.want = want;
    this.launchParam = launchParam;
    actionCreate(want);
    createDbInsertData(this.context);

    // 接续场景：恢复迁移数据
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      hilog.info(DOMAIN_NUMBER, TAG, 'onCreate: CONTINUATION');
      // 从 want.parameters 恢复视频链接
      if (want.parameters?.networkVideoSrc) {
        const videoUrl = want.parameters.networkVideoSrc as string;
        AppStorage.setOrCreate('networkVideoSrc', videoUrl);
        hilog.info(DOMAIN_NUMBER, TAG, `接续恢复视频链接: ${videoUrl}`);
      }
      // 保证迁移后依然可以迁移回源端
      this.context.setMissionContinueState(AbilityConstant.ContinueState.ACTIVE);
      // 触发页面恢复
      this.context.restoreWindowStage(this.storage);
      return;
    }

    // 处理分享链接（AppLinking/碰一碰）
    const receivedLink = want.parameters?.['link'] || want.uri;
    if (receivedLink) {
      AppStorage.setOrCreate<string>('sharedVideoUrl', receivedLink.toString());
    }

    // 加载沉浸Tab设置（同步加载）
    this.loadImmersiveSettingSync();

    // 原有扫码逻辑保留
    let uri = want?.uri;
    setTimeout(() => {
      if (uri) {
        router.pushUrl({
          url: 'pages', // 直接跳转到视频页面
          params: {
            videoUrl: uri,
            source: 'scan'
          }
        });
      }
    })

    // 保留原有逻辑
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    hilog.info(DOMAIN_NUMBER, TAG, `Ability onCreate: ${JSON.stringify(want?.parameters)}`);
    if (want?.parameters?.params) {
      // want.parameters.params 对应 postCardAction() 中 params 内容
      let params: Record<string, Object> = JSON.parse(want.parameters.params as string);
      this.selectPage = params.targetPage as string;
      hilog.info(DOMAIN_NUMBER, TAG, `onCreate selectPage: ${this.selectPage}`);
    }
    this.context.eventHub.emit('urlUpdate', receivedLink)
  }

  // 热启动场景通过onNewWant回调获取码值信息
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    actionNewWant(want, this);
    createDbInsertData(this.context);

    // 接续场景：恢复迁移数据
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      hilog.info(DOMAIN_NUMBER, TAG, 'onNewWant: CONTINUATION');
      // 从 want.parameters 恢复视频链接
      if (want.parameters?.networkVideoSrc) {
        const videoUrl = want.parameters.networkVideoSrc as string;
        AppStorage.setOrCreate('networkVideoSrc', videoUrl);
        hilog.info(DOMAIN_NUMBER, TAG, `接续恢复视频链接: ${videoUrl}`);
      }
      // 保证迁移后依然可以迁移回源端
      this.context.setMissionContinueState(AbilityConstant.ContinueState.ACTIVE);
      // 触发页面恢复
      this.context.restoreWindowStage(this.storage);
      return;
    }

    const receivedLink = want.parameters?.['link'] || want.uri;
    if (receivedLink) {
      AppStorage.setOrCreate<string>('sharedVideoUrl', receivedLink.toString());
      // 触发页面刷新逻辑
      this.currentWindowStage?.loadContent('pages/HomePage')
    }
    // 保留原有逻辑
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
  }

  onDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    actionWindowStageCreate(windowStage);
    this.currentWindowStage = windowStage;

    // 提前创建WindowUtil
    let windowClass: window.Window = windowStage.getMainWindowSync();
    let windowUtil: WindowUtil = new WindowUtil(windowClass);
    AppStorage.setOrCreate('windowUtil', windowUtil);

    // 1. 设置全屏布局模式（沉浸Tab需要）——必须等待完成后才能读取正确的安全区高度
    windowClass.setWindowLayoutFullScreen(true).then(() => {
      console.info('Succeeded in setting the window layout to full-screen mode.');

      // 2. 获取并存储安全区高度——全屏模式设置完成后读取，确保值正确
      let avoidAreaNav = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      let bottomRectHeight = avoidAreaNav.bottomRect.height;
      AppStorage.setOrCreate('bottomRectHeight', bottomRectHeight);

      let avoidAreaSystem = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      let topRectHeight = avoidAreaSystem.topRect.height;
      AppStorage.setOrCreate('topRectHeight', topRectHeight);

      console.info(`安全区高度: top=${topRectHeight}, bottom=${bottomRectHeight}`);

      // 3. 加载页面——AppStorage已有正确值，页面渲染时直接使用
      windowStage.loadContent('pages/Index', (err, data) => {
        if (err.code) {
          return;
        }

        // 显示状态栏（根据沉浸设置决定）
      const isImmersiveStatusBar = AppStorage.get<boolean>('isImmersiveStatusBar') ?? false;
      if (isImmersiveStatusBar) {
        // 状态栏沉浸模式：隐藏状态栏，只显示导航栏
        windowClass.setWindowSystemBarEnable(['navigation']).then(() => {
          console.info('沉浸模式：状态栏已隐藏');
        }).catch((err: BusinessError) => {
          console.error(`Failed to set system bar enabled. Code is ${err.code}, message is ${err.message}`);
        });
      } else {
        // 正常模式：显示状态栏和导航栏
        windowClass.setWindowSystemBarEnable(['status', 'navigation']).then(() => {
          console.info('Succeeded in setting system bar enabled.');
        }).catch((err: BusinessError) => {
          console.error(`Failed to set system bar enabled. Code is ${err.code}, message is ${err.message}`);
        });
      }

      // 配置窗口整体底色（导航条区域背景色）
      windowClass.setWindowBackgroundColor('#F1F3F5');

      // 初始化断点监听（在页面加载完成后）
      windowUtil.updateWindowInfo();
    });
    }).catch((err: BusinessError) => {
      console.error(`Failed to set full-screen mode. Code: ${err.code}, message: ${err.message}`);
      // 全屏模式失败时降级：仍需读取安全区并加载页面
      let avoidAreaNav = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      AppStorage.setOrCreate('bottomRectHeight', avoidAreaNav.bottomRect.height);
      let avoidAreaSystem = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      AppStorage.setOrCreate('topRectHeight', avoidAreaSystem.topRect.height);
      windowStage.loadContent('pages/Index');
    });
  }

  // 同步加载沉浸Tab设置
  private loadImmersiveSettingSync(): void {
    try {
      // 同步获取preferences
      const prefs = preferences.getPreferencesSync(this.context, { name: 'immersive_settings' });
      const savedValue = prefs.getSync('isImmersiveTab', false) as boolean;
      AppStorage.setOrCreate('isImmersiveTab', savedValue);
      hilog.info(DOMAIN_NUMBER, TAG, `沉浸Tab设置已加载: ${savedValue}`);

      // 状态栏沉浸设置不记忆，每次启动默认关闭
      AppStorage.setOrCreate('isImmersiveStatusBar', false);
      hilog.info(DOMAIN_NUMBER, TAG, '状态栏沉浸设置不记忆，默认关闭');
    } catch (error) {
      hilog.error(DOMAIN_NUMBER, TAG, `加载沉浸Tab设置失败: ${JSON.stringify(error)}`);
      AppStorage.setOrCreate('isImmersiveTab', false);
      AppStorage.setOrCreate('isImmersiveStatusBar', false);
    }
  }

  // 应用接续：保存迁移数据
  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    hilog.info(DOMAIN_NUMBER, TAG, `onContinue version = ${wantParam.version}, targetDevice: ${wantParam.targetDevice}`);

    // 从 AppStorage 获取当前播放的视频链接
    const networkVideoSrc = AppStorage.get<string>('networkVideoSrc');
    if (networkVideoSrc) {
      wantParam['networkVideoSrc'] = networkVideoSrc;
      hilog.info(DOMAIN_NUMBER, TAG, `接续保存视频链接: ${networkVideoSrc}`);
    }

    return AbilityConstant.OnContinueResult.AGREE;
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
    this.currentWindowStage = null;
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');
  }
}