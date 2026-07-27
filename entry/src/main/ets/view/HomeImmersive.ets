import { TabDataModel } from '../model/TabDataModel';
import { TabViewModel } from '../viewmodel/TabViewModel';
import { HomePage } from '../pages/HomePage';
import { SecondPage } from '../pages/SecondPage';
import { MinePage } from '../pages/MinePage';
import { router } from '@kit.ArkUI';
import { common as abilityCommon } from '@kit.AbilityKit';
import { WindowUtil } from '../utils/WindowUtil';

@Component
export struct HomeImmersive {
  @StorageLink('currentWidthBreakpoint') currentWidthBreakpoint: string = 'sm';
  @StorageLink('isImmersiveTab') isImmersiveTab: boolean = true;
  @StorageLink('currentTabIndex') firstLevelIndex: number = 0;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageLink('windowUtil') windowUtil: WindowUtil | undefined = undefined;
  @State secondLevelIndex: number = 0;
  @State tabViewModel: TabViewModel = new TabViewModel();
  @State tabData: TabDataModel = this.tabViewModel.getTabMap();
  private shortcutNavigateCallback = (url: string) => {
    console.info('HomeImmersive: 收到快捷方式导航事件, url=', url);
    router.pushUrl({ url: url }).catch((err: Error) => {
      console.error('Failed to navigate to shortcut page:', err);
    });
  };

  aboutToAppear(): void {
    // 用真实 context 重建 tabMap，获取正确的本地化 Tab 名称
    try {
      const ctx = getContext(this) as abilityCommon.UIAbilityContext;
      this.tabViewModel.initWithContext(ctx);
      this.tabData = this.tabViewModel.getTabMap();
    } catch (e) {
      console.error('HomeImmersive: Failed to init tabViewModel with context:', e);
    }

    // 订阅快捷方式导航事件
    try {
      const context = getContext(this) as abilityCommon.UIAbilityContext;
      context.eventHub.on('shortcutNavigate', this.shortcutNavigateCallback);
    } catch (e) {
      console.error('HomeImmersive: Failed to subscribe shortcutNavigate event:', e);
    }

    // 初始化当前Tab索引
    AppStorage.setOrCreate('currentTabIndex', 0);

    const initialTabIndex = AppStorage.get<number>('initialTabIndex');
    if (initialTabIndex !== undefined && initialTabIndex !== null) {
      AppStorage.setOrCreate('currentTabIndex', initialTabIndex);
      AppStorage.delete('initialTabIndex');
    }

    // 快捷方式跳转
    this.checkShortcutNavigation();

    // 接续跳转
    this.checkContinuationNavigation();
  }

  aboutToDisappear(): void {
    try {
      const context = getContext(this) as abilityCommon.UIAbilityContext;
      context.eventHub.off('shortcutNavigate', this.shortcutNavigateCallback);
    } catch (e) {
      console.error('HomeImmersive: Failed to unsubscribe shortcutNavigate event:', e);
    }
  }

  checkShortcutNavigation(): void {
    const shortCutPage = AppStorage.get<string>('ShortCutPage');
    if (shortCutPage !== undefined && shortCutPage !== null && shortCutPage !== '') {
      console.info('HomeImmersive: 准备跳转到快捷方式页面, url=', shortCutPage);
      setTimeout(() => {
        router.pushUrl({ url: shortCutPage }).catch((err: Error) => {
          console.error('Failed to navigate to shortcut page:', err);
        });
        AppStorage.delete('ShortCutPage');
      }, 100);
    }
  }

  checkContinuationNavigation(): void {
    const continuationPageUrl = AppStorage.get<string>('continuationPageUrl');
    if (continuationPageUrl !== undefined && continuationPageUrl !== null && continuationPageUrl !== '') {
      const continuationRouteParams = AppStorage.get<string>('continuationRouteParams');
      let params: Object | undefined = undefined;
      if (continuationRouteParams) {
        try {
          params = JSON.parse(continuationRouteParams);
        } catch (e) {
          console.error('Failed to parse continuation route params:', e);
        }
      }

      AppStorage.setOrCreate('isContinuation', true);
      AppStorage.delete('SecondPageSplitMode');

      setTimeout(() => {
        router.pushUrl({ url: continuationPageUrl, params: params }).catch((err: Error) => {
          console.error('Failed to navigate to continuation page:', err);
        });
        AppStorage.delete('continuationPageUrl');
        AppStorage.delete('continuationRouteParams');
      }, 100);
    }
  }

  getTabSymbol(index: number): Resource {
    switch (index) {
      case 0:
        return $r('sys.symbol.media_center');
      case 1:
        return $r('sys.symbol.mic_fill');
      case 2:
        return $r('sys.symbol.person');
      default:
        return $r('sys.symbol.house');
    }
  }

  // 是否为平板模式（lg/xl断点）
  private isTabletMode(): boolean {
    return this.currentWidthBreakpoint === 'lg' || this.currentWidthBreakpoint === 'xl';
  }

  @Builder
  tabBuilder(name: string, index: number) {
    Column() {
      SymbolGlyph(this.getTabSymbol(index))
        .fontSize(24)
        .fontColor([index === this.firstLevelIndex ? $r('sys.color.brand') : $r('sys.color.icon_secondary')])
      Text(name)
        .fontSize(10)
        .fontWeight(500)
        .fontColor(index === this.firstLevelIndex ? '#0A59F7' : '#999999')
        .margin({ top: 4 })
    }
    .width('100%')
    .height(!this.isImmersiveTab && this.isTabletMode() ? 100 : '100%')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Tabs({
        barPosition: BarPosition.End,
        index: this.firstLevelIndex
      }) {
        TabContent() {
          HomePage({ mainWindowInfo: this.windowUtil!.mainWindowInfo })
        }
        .tabBar(this.tabBuilder(this.tabData.getFirstList()[0], 0))

        TabContent() {
          SecondPage({ mainWindowInfo: this.windowUtil!.mainWindowInfo })
        }
        .tabBar(this.tabBuilder(this.tabData.getFirstList()[1], 1))

        TabContent() {
          MinePage()
        }
        .tabBar(this.tabBuilder(this.tabData.getFirstList()[2], 2))
      }
      .barPosition(BarPosition.End)
      .vertical(false)
      .onChange((index: number) => {
        this.firstLevelIndex = index;
        AppStorage.setOrCreate('currentTabIndex', index);
      })
      .scrollable(false)
      .height('100%')
      .width('100%')
      .expandSafeArea([SafeAreaType.SYSTEM])
      .padding({ bottom: px2vp(this.bottomRectHeight) })
    }
}