import { HomeImmersive } from '../view/HomeImmersive';
import { GlobalInfoModel } from '../common/GlobalInfoModel';

@Entry
@Component
struct Index {
  @Provide('NavPathStack') pageStack: NavPathStack = new NavPathStack();
  @StorageLink('GlobalInfoModel') globalInfoModel: GlobalInfoModel = AppStorage.get('GlobalInfoModel')!;

  aboutToAppear(): void {
    console.info('Index.ets aboutToAppear - Immersive default mode');
  }

  build() {
    Column() {
      HomeImmersive()
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM])
  }
}