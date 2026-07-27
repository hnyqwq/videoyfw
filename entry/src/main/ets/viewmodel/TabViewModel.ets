import { TabDataModel } from '../model/TabDataModel';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';

// 兜底默认值，需与 string.json 中资源值保持一致（Home=主页, Second=文本转语音, Mine=我的）
const DEFAULT_TAB_HOME: string = '主页';
const DEFAULT_TAB_SECOND: string = '文本转语音';
const DEFAULT_TAB_MINE: string = '我的';

export class TabViewModel {
  private tabMap: TabDataModel;

  constructor() {
    // 构造时无 context，使用与资源一致的兜底默认值
    this.tabMap = new TabDataModel(this.buildTabMap(undefined));
  }

  /**
   * 在组件 aboutToAppear 中调用，传入真实 context 后用 resourceManager 读取本地化字符串重建 tabMap。
   * 调用后需由调用方刷新关联的 @State tabData。
   */
  initWithContext(context: common.UIAbilityContext): void {
    this.tabMap = new TabDataModel(this.buildTabMap(context));
  }

  private buildTabMap(context: common.UIAbilityContext | undefined): Map<string, string[]> {
    let tabMap: Map<string, string[]> = new Map();
    if (context) {
      try {
        tabMap.set(context.resourceManager.getStringSync($r('app.string.Home').id), []);
        tabMap.set(context.resourceManager.getStringSync($r('app.string.Second').id), []);
        tabMap.set(context.resourceManager.getStringSync($r('app.string.Mine').id), []);
        return tabMap;
      } catch (error) {
        hilog.error(0x0000, 'testTag', 'Failed to get string. Cause: %{public}s', JSON.stringify(error) ?? '');
      }
    }
    // context 不可用或读取失败时使用兜底默认值
    tabMap.set(DEFAULT_TAB_HOME, []);
    tabMap.set(DEFAULT_TAB_SECOND, []);
    tabMap.set(DEFAULT_TAB_MINE, []);
    return tabMap;
  }

  getTabMap(): TabDataModel {
    return this.tabMap;
  }

  getTabNameOfFirstLevel(index: number): string {
    return this.tabMap.getFirstList()[index];
  }

  getTabNameOfSecondLevel(firstTab: string, index: number): string {
    return this.tabMap.getSecondList(firstTab)[index];
  }
}