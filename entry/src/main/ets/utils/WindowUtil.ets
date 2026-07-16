import { window, display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { WindowInfo } from './WindowInfo';

export class WindowUtil {
  public mainWindowInfo: WindowInfo = new WindowInfo();
  private mainWindow: window.Window;
  public uiContext: UIContext | null = null;
  private densityPixels: number = 1;

  constructor(mainWindow: window.Window) {
    this.mainWindow = mainWindow;
    // 获取屏幕密度用于 px -> vp 转换
    try {
      this.densityPixels = display.getDefaultDisplaySync().densityPixels;
    } catch (e) {
      this.densityPixels = 1;
    }
  }

  setUIContext(uiContext: UIContext): void {
    this.uiContext = uiContext;
  }

  updateWindowInfo(): void {
    try {
      // 首次获取断点
      const width = this.mainWindow.getWindowProperties().windowRect.width;
      this.mainWindowInfo.widthBp = this.calcWidthBreakpoint(width);
      // 同步到AppStorage（兼容旧组件）
      AppStorage.setOrCreate('currentWidthBreakpoint', this.mainWindowInfo.widthBp);
      console.info(`[WindowUtil] 初始断点: ${this.mainWindowInfo.widthBp}, widthPx=${width}, widthVp=${width / this.densityPixels}`);

      // 注册窗口尺寸变化监听（折叠屏折叠/展开、横竖屏切换均触发此事件）
      this.mainWindow.on('windowSizeChange', (data: window.Size) => {
        const newBp = this.calcWidthBreakpoint(data.width);
        console.info(`[WindowUtil] windowSizeChange: width=${data.width}, oldBp=${this.mainWindowInfo.widthBp}, newBp=${newBp}`);
        if (this.mainWindowInfo.widthBp !== newBp) {
          this.mainWindowInfo.widthBp = newBp;
          AppStorage.setOrCreate('currentWidthBreakpoint', newBp);
        }
        // 窗口尺寸变化时同步刷新安全区高度（折叠屏折叠/展开后导航条高度可能变化）
        const navAvoidArea = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        AppStorage.setOrCreate('bottomRectHeight', navAvoidArea.bottomRect.height);
        const sysAvoidArea = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        AppStorage.setOrCreate('topRectHeight', sysAvoidArea.topRect.height);
        console.info(`[WindowUtil] windowSizeChange: safeArea updated, bottom=${navAvoidArea.bottomRect.height}, top=${sysAvoidArea.topRect.height}`);
      });
    } catch (error) {
      let err = error as BusinessError;
      console.error(`[WindowUtil] 初始化失败. Code: ${err.code}, message: ${err.message}`);
    }
  }

  private calcWidthBreakpoint(widthPx: number): string {
    const widthVp = widthPx / this.densityPixels;
    if (widthVp >= 1440) return 'xl';
    if (widthVp >= 840) return 'lg';
    if (widthVp >= 600) return 'md';
    return 'sm';
  }
}
