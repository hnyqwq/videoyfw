import { textToSpeech } from '@kit.CoreSpeechKit';//语音
import { BusinessError } from '@kit.BasicServicesKit';
import router from '@ohos.router';
import { WindowInfo } from '../utils/WindowInfo';

let ttsEngine: textToSpeech.TextToSpeechEngine;

@Entry
@Component
export struct SecondPage {
  @ObjectLink mainWindowInfo: WindowInfo;
  @StorageLink('networkVideoSrc') networkVideoSrc: string = '';
  @StorageLink('isImmersiveTab') isImmersiveTab: boolean = false;
  @StorageLink('isAtomicServiceBarImmersive') isAtomicServiceBarImmersive: boolean = false;
  @StorageProp('topRectHeight')
  topRectHeight: number = 0;
  @StorageProp('bottomRectHeight')
  bottomRectHeight: number = 0;
  @State createCount: number = 0;
  @StorageLink('isPlaying') isPlaying: boolean = false;

  aboutToAppear() {
    // 保存当前页面信息到 AppStorage,供接续功能使用
    AppStorage.setOrCreate('currentPageUrl', 'XHTB/TextToSpeechPage');
    AppStorage.delete('currentRouteParams');
  }

  aboutToDisappear() {
    try {
      const isBusy = ttsEngine?.isBusy();
      if (isBusy) {
        ttsEngine?.stop();
        AppStorage.setOrCreate('isPlaying', false);
        ttsEngine?.shutdown();
      }
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error(`The ttsEngine invoke error, the code is ${error.code}, the message is ${error.message}`);
    }
  }

  build() {
    Column({ space: 0 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
          .margin({ left: 16 })
          .onClick(() => router.back())
      }
      .width('100%')
      .height(56)
      .padding({ top: px2vp(this.topRectHeight) + (this.isAtomicServiceBarImmersive ? 0 : 50) })

      Column({ space: 20 }) {
        Text($r('app.string.sub_title2_value1'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 20 })

        TextArea({ placeholder: $r('app.string.speak'), text: this.networkVideoSrc })
          .margin({
            left: $r('sys.float.padding_level16'),
            right: $r('sys.float.padding_level16'),
          })
          .onChange((networkVideoSrc: string) => {
            this.networkVideoSrc = networkVideoSrc;
            AppStorage.set('networkVideoSrc', networkVideoSrc);
          })
        Text($r('app.string.ai_core_speech_support'))
          .padding({ top: 2 , left: 24, right: 24 })
          .fontSize(11)
          .maxFontScale(1.75)
          .width('100%')
          .fontColor($r('app.color.font_secondary'))
          .fontFamily('HarmonyHeiTi')
          .textAlign(TextAlign.Center)
        Row({ space: 40 }) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause') : $r('sys.symbol.play'))
              .fontSize(24)
              .fontColor([$r('sys.color.icon_primary')])
          }
          .margin({ top: 10 })
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            if (this.isPlaying) {
              // 正在播放，点击停止
              try {
                ttsEngine?.stop();
                ttsEngine?.shutdown();
              } catch (err) {
                const error: BusinessError = err as BusinessError;
                console.error(`The ttsEngine invoke error, the code is ${error.code}, the message is ${error.message}`);
              }
              AppStorage.setOrCreate('isPlaying', false);
            } else {
              // 未播放，点击开始
              try {
                this.createByCallback();
              } catch (err) {
                const error: BusinessError = err as BusinessError;
                console.error(`CreateEngine error, the code is ${error.code}, the message is ${error.message}`);
              }
            }
          })
          .width('40vp')

          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(24)
              .fontColor([$r('sys.color.icon_primary')])
          }
          .margin({ top: 10 })
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            try {
              ttsEngine?.stop();
              ttsEngine?.shutdown();
            } catch (err) {
              const error: BusinessError = err as BusinessError;
              console.error(`The ttsEngine invoke error, the code is ${error.code}, the message is ${error.message}`);
            }
            AppStorage.setOrCreate('isPlaying', false);
          })
          .width('40vp')
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .layoutWeight(1)
    }
    .height('100%')
    .padding({ bottom: px2vp(this.bottomRectHeight) + (this.isImmersiveTab ? 84 : 0) })
  }

  createByCallback() {
    let extraParam: Record<string, string> = { 'style': 'interaction-broadcast', 'locate': 'CN', 'name': 'EngineName' };
    let initParamsInfo: textToSpeech.CreateEngineParams = {
      language: 'zh-CN',
      person: 0,
      online: 1,
      extraParams: extraParam
    };
    textToSpeech.createEngine(initParamsInfo,
      (err: BusinessError, textToSpeechEngine: textToSpeech.TextToSpeechEngine) => {
        if (!err) {
          ttsEngine = textToSpeechEngine;
          this.createCount++;
          this.speak();
        } else {
          console.log('Fail to createEngine.');
        }
      });
  }

  speak() {
    let speakListener: textToSpeech.SpeakListener = {
      onStart(requestId: string, response: textToSpeech.StartResponse) {
        console.log('onStart');
        AppStorage.setOrCreate('isPlaying', true);
      },
      onComplete(requestId: string, response: textToSpeech.CompleteResponse) {
        console.log('onComplete - 合成完成，轮询等待播放结束');
        // onComplete在合成完成时触发，音频可能仍在播放
        // 轮询isBusy()直到播放真正结束
        const pollBusy = () => {
          try {
            if (ttsEngine && ttsEngine.isBusy()) {
              setTimeout(pollBusy, 300);
            } else {
              AppStorage.setOrCreate('isPlaying', false);
              ttsEngine?.shutdown();
            }
          } catch (e) {
            AppStorage.setOrCreate('isPlaying', false);
          }
        };
        setTimeout(pollBusy, 300);
      },
      onStop(requestId: string, response: textToSpeech.StopResponse) {
        console.log('onStop');
        AppStorage.setOrCreate('isPlaying', false);
        ttsEngine?.shutdown();
      },
      onData(requestId: string, audio: ArrayBuffer, response: textToSpeech.SynthesisResponse) {
        console.log('onData');
      },
      onError(requestId: string, errorCode: number, errorMessage: string) {
        console.log('onError');
        AppStorage.setOrCreate('isPlaying', false);
        ttsEngine?.shutdown();
      }
    };
    ttsEngine?.setListener(speakListener);
    let extraParam: Record<string, string | number> = {
      'queueMode': 0,
      'speed': 1,
      'volume': 2,
      'pitch': 1,
      'languageContext': 'zh-CN',
      'audioType': 'pcm',
      'soundChannel': 3,
      'playType': 1
    }
    let speakParams: textToSpeech.SpeakParams = {
      requestId: '123456-a',
      extraParams: extraParam
    };
    ttsEngine?.speak(this.networkVideoSrc, speakParams);//originalText
  };
}