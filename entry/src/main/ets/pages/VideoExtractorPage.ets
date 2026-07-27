import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, AtomicServiceWeb, AtomicServiceWebController } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import router from '@ohos.router';

class VideoLink {
  url: string = '';
  type: string = '';
  format: string = '';
}

class BaseUrlInfo {
  protocol: string = '';
  origin: string = '';
  basePath: string = '';
}

@Entry
@Component
struct VideoExtractorPage {
  @State loadProgress: number = 0;
  @State webViewVisible: boolean = false;
  @State webSrc: string = 'about:blank';
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageLink('isImmersiveStatusBar') isImmersiveStatusBar: boolean = false;
  @StorageLink('networkVideoSrc') networkVideoSrc: string = '';
  @StorageLink('extractedVideos') extractedVideos: VideoLinkItem[] = [];

  @State webController: AtomicServiceWebController = new AtomicServiceWebController();
  private currentUrl: string = '';
  private webViewTimeoutId: number = 0;
  private collectedVideoUrls: Set<string> = new Set();

  private readonly videoExtensions: string[] = [
    '.mp4', '.webm', '.mov', '.mkv', '.avi', '.flv', '.wmv', '.m4v', '.3gp', '.ogv', '.ts', '.m3u8'
  ];

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params?.['initialUrl']) {
      this.currentUrl = params['initialUrl'];
      this.extractVideos();
    } else {
      router.back();
    }
  }

  aboutToDisappear(): void {
    this.clearWebViewTimeout();
  }

  // 解析baseUrl获取协议和域名
  private parseBaseUrl(baseUrl: string): BaseUrlInfo {
    let protocol = 'https:';
    let origin = '';
    let basePath = '';

    if (baseUrl.startsWith('https://')) {
      protocol = 'https:';
    } else if (baseUrl.startsWith('http://')) {
      protocol = 'http:';
    }

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

  // 将相对URL转换为绝对URL
  private toAbsoluteUrl(url: string, baseUrl: string): string {
    if (!url) return '';
    url = url.trim();

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    const parsed = this.parseBaseUrl(baseUrl);

    if (url.startsWith('//')) {
      return parsed.protocol + url;
    }

    if (url.startsWith('/')) {
      return parsed.origin + url;
    }

    const lastSlashIndex = parsed.basePath.lastIndexOf('/');
    if (lastSlashIndex > 0) {
      return parsed.origin + parsed.basePath.substring(0, lastSlashIndex + 1) + url;
    }
    return parsed.origin + '/' + url;
  }

  // 执行正则匹配，返回结果数组
  private execRegex(regex: RegExp, text: string): string[][] {
    const results: string[][] = [];
    const globalRegex = new RegExp(regex.source, regex.flags);
    let match: RegExpExecArray | null = globalRegex.exec(text);

    while (match !== null) {
      const arr: string[] = [];
      for (let i = 0; i < match.length; i++) {
        arr.push(match[i]);
      }
      results.push(arr);
      match = globalRegex.exec(text);
    }
    return results;
  }

  // 提取视频链接
  private extractVideoLinks(html: string, baseUrl: string): VideoLink[] {
    const links: VideoLink[] = [];
    const addedUrls = new Set<string>();

    const addLink = (url: string, type: string): void => {
      let cleanUrl = url.replace(/[\\'"\s]+$/g, '');
      const absoluteUrl = this.toAbsoluteUrl(cleanUrl, baseUrl);
      if (!absoluteUrl || addedUrls.has(absoluteUrl)) return;

      const lowerUrl = absoluteUrl.toLowerCase();
      let format = 'unknown';
      for (const ext of this.videoExtensions) {
        if (lowerUrl.includes(ext)) {
          format = ext.replace('.', '');
          break;
        }
      }

      addedUrls.add(absoluteUrl);
      const link = new VideoLink();
      link.url = absoluteUrl;
      link.type = type;
      link.format = format;
      links.push(link);
    };

    // 1. 提取 <video src="..."> 标签
    const videoSrcMatches = this.execRegex(/<video[^>]+src=["']([^"']+)["']/gi, html);
    for (const match of videoSrcMatches) {
      if (match.length > 1) addLink(match[1], 'video_tag');
    }

    // 2. 提取 <video><source src="..."> 标签
    const sourceSrcMatches = this.execRegex(/<source[^>]+src=["']([^"']+)["']/gi, html);
    for (const match of sourceSrcMatches) {
      if (match.length > 1) addLink(match[1], 'source_tag');
    }

    // 3. 提取 <a href="*.mp4"> 等链接
    const hrefMatches = this.execRegex(/<a[^>]+href=["']([^"']+)["']/gi, html);
    for (const match of hrefMatches) {
      if (match.length > 1) {
        const lowerUrl = match[1].toLowerCase();
        for (const ext of this.videoExtensions) {
          if (lowerUrl.includes(ext)) {
            addLink(match[1], 'link_tag');
            break;
          }
        }
      }
    }

    // 4. 提取 iframe 中的视频链接
    const iframeMatches = this.execRegex(/<iframe[^>]+src=["']([^"']+)["']/gi, html);
    for (const match of iframeMatches) {
      if (match.length > 1) {
        const lowerUrl = match[1].toLowerCase();
        if (lowerUrl.includes('youtube') || lowerUrl.includes('vimeo') ||
            lowerUrl.includes('bilibili') || lowerUrl.includes('youku') ||
            lowerUrl.includes('iqiyi') || lowerUrl.includes('video')) {
          addLink(match[1], 'iframe_embed');
        }
      }
    }

    // 5. 提取 JSON/JavaScript 中的视频URL
    const jsonUrlMatches = this.execRegex(
      /["']((https?:)?\/\/[^"']+\.(?:mp4|webm|mov|mkv|avi|flv|m3u8|ts)(\?[^"']*)?)["']/gi,
      html
    );
    for (const match of jsonUrlMatches) {
      if (match.length > 1) addLink(match[1], 'JS/JSON');
    }

    // 6. 提取 poster 属性中的视频链接
    const posterMatches = this.execRegex(/poster=["']([^"']+)["']/gi, html);
    for (const match of posterMatches) {
      if (match.length > 1) {
        const lowerUrl = match[1].toLowerCase();
        for (const ext of this.videoExtensions) {
          if (lowerUrl.includes(ext)) {
            addLink(match[1], 'poster_attr');
            break;
          }
        }
      }
    }

    // 7. 提取 data-src 属性
    const dataSrcMatches = this.execRegex(/data-(?:src|source|video)=["']([^"']+)["']/gi, html);
    for (const match of dataSrcMatches) {
      if (match.length > 1) addLink(match[1], 'data_attr');
    }

    // 8. 提取视频托管域名的URL
    const videoHostMatches = this.execRegex(
      /["']((https?:)?\/\/[^"']*(?:videos\.pexels|player\.vimeo|vimeo\.com|\.cloudfront\.net|\.akamaized\.net|cdn\.[^"']+)[^"']*)["']/gi,
      html
    );
    for (const match of videoHostMatches) {
      if (match.length > 1) {
        const url = match[1];
        if (url.includes('.mp4') || url.includes('.webm') || url.includes('.m3u8') ||
            url.includes('video') || url.includes('play') || url.includes('embed')) {
          addLink(url, 'video_host');
        }
      }
    }

    // 9. 提取JSON中的video_url字段
    const jsonVideoMatches = this.execRegex(
      /["'](?:video_url|videoUrl|video_src|videoSrc|video_link|videoLink|file_url|fileUrl|url)["']\s*:\s*["']([^"']+)["']/gi,
      html
    );
    for (const match of jsonVideoMatches) {
      if (match.length > 1) addLink(match[1], 'json_field');
    }

    // 10. 提取所有包含视频扩展名的URL（无引号包裹）
    const rawUrlMatches = this.execRegex(
      /(https?:\/\/[^\s"'<>]+\.(?:mp4|webm|mov|mkv|avi|flv|m3u8|ts)(?:\?[^\s"'<>]*)?)/gi,
      html
    );
    for (const match of rawUrlMatches) {
      if (match.length > 1) addLink(match[1], 'raw_url');
    }

    return links;
  }

  // 开始WebView提取
  private extractVideos(): void {
    let url = this.currentUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://' + url;
    }

    this.currentUrl = url;
    this.loadProgress = 0;
    this.webSrc = url;
    this.collectedVideoUrls.clear();

    // 设置60秒超时
    this.webViewTimeoutId = setTimeout(() => {
      if (this.webViewVisible && this.loadProgress < 100) {
        hilog.error(0x0000, 'VideoExtractor', 'WebView loading timeout');
        this.webViewVisible = false;
        promptAction.showToast({ message: $r('app.string.ve_load_timeout_check_network') });
        router.back();
      }
    }, 60000);

    this.webViewVisible = true;
  }

  // 清除超时定时器
  private clearWebViewTimeout(): void {
    if (this.webViewTimeoutId) {
      clearTimeout(this.webViewTimeoutId);
      this.webViewTimeoutId = 0;
    }
  }

  // 处理通过onLoadIntercept拦截收集到的视频URL
  private processCollectedVideos(): void {
    this.clearWebViewTimeout();

    const videoItems: VideoLinkItem[] = [];
    const addedUrls = new Set<string>();
    for (const url of this.collectedVideoUrls) {
      if (addedUrls.has(url)) continue;
      addedUrls.add(url);
      const lowerUrl = url.toLowerCase();
      let format = 'unknown';
      for (const ext of this.videoExtensions) {
        if (lowerUrl.includes(ext)) {
          format = ext.replace('.', '');
          break;
        }
      }
      const item = new VideoLinkItem();
      item.url = url;
      item.type = 'resource';
      item.format = format;
      item.size = 0;
      item.sizeText = '';
      videoItems.push(item);
    }

    hilog.info(0x0000, 'VideoExtractor', `Found ${videoItems.length} video links via intercept (collected ${this.collectedVideoUrls.size} URLs)`);
    this.extractedVideos = videoItems;
    this.webViewVisible = false;

    if (videoItems.length === 0) {
      promptAction.showToast({ message: `未找到视频（拦截到${this.collectedVideoUrls.size}个URL）`, duration: 3000 });
    } else {
      promptAction.showToast({ message: $r('app.string.found_videos', videoItems.length) });
    }

    router.back();
  }

  build() {
    Column() {
      // 顶部避让状态栏和元服务胶囊（胶囊固定避让50vp）
      Column()
        .height((this.isImmersiveStatusBar ? 0 : px2vp(this.topRectHeight)) + 50)

      // 顶部进度条和操作栏
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
          .onClick(() => {
            this.processCollectedVideos();
          })

        Button($r('app.string.ve_cancel'))
          .fontSize(12)
          .height(32)
          .onClick(() => {
            this.clearWebViewTimeout();
            this.webViewVisible = false;
            router.back();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))

      Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
        .width('100%')
        .color($r('sys.color.ohos_id_color_activated'))

      AtomicServiceWeb({
        src: this.webSrc,
        controller: this.webController,
        mixedMode: MixedMode.All,
        onLoadIntercept: (event: OnLoadInterceptEvent) => {
          try {
            const reqUrl = event.data.getRequestUrl();
            hilog.info(0x0000, 'VideoExtractor', `Intercept URL: ${reqUrl}`);
            if (reqUrl) {
              const lowerUrl = reqUrl.toLowerCase();
              for (const ext of this.videoExtensions) {
                if (lowerUrl.includes(ext)) {
                  hilog.info(0x0000, 'VideoExtractor', `>>> Video matched: ${reqUrl}`);
                  this.collectedVideoUrls.add(reqUrl);
                  break;
                }
              }
            }
          } catch (e) {
            hilog.error(0x0000, 'VideoExtractor', `Intercept error: ${e}`);
          }
          return false;
        },
        onPageBegin: (event: OnPageBeginEvent) => {
          hilog.info(0x0000, 'VideoExtractor', `Page begin: ${event?.url}`);
        },
        onPageEnd: () => {
          hilog.info(0x0000, 'VideoExtractor', 'Page end, ready to extract');
          this.loadProgress = 100;
          promptAction.showToast({ message: $r('app.string.ve_page_ready_to_extract') });
        },
        onProgressChange: (event: OnProgressChangeEvent) => {
          if (event?.newProgress !== undefined) {
            this.loadProgress = event.newProgress;
            hilog.info(0x0000, 'VideoExtractor', `Loading progress: ${this.loadProgress}%`);
          }
        },
        onErrorReceive: (event: OnErrorReceiveEvent) => {
          const errorInfo = event?.error?.getErrorInfo() ?? '';
          hilog.error(0x0000, 'VideoExtractor', `WebView error: ${errorInfo}`);
          if (!errorInfo || errorInfo.includes('domain') || errorInfo.includes('block')) {
            promptAction.showToast({ message: $r('app.string.web_domain_not_configured') });
          } else {
            promptAction.showToast({ message: $r('app.string.webpage_load_error', errorInfo) });
          }
        },
        onHttpErrorReceive: (event: OnHttpErrorReceiveEvent) => {
          const responseCode = event?.response?.getResponseCode() ?? 0;
          hilog.error(0x0000, 'VideoExtractor', `HTTP error: ${responseCode}`);

          if (responseCode === 401) {
            promptAction.showToast({ message: $r('app.string.website_login_required') });
          } else if (responseCode === 403 || responseCode === 404) {
            this.clearWebViewTimeout();
            this.webViewVisible = false;
            promptAction.showToast({ message: $r('app.string.webpage_access_failed', responseCode) });
            router.back();
          }
        }
      })
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_background'))
    .expandSafeArea([SafeAreaType.SYSTEM])
  }
}

class VideoLinkItem {
  url: string = '';
  type: string = '';
  format: string = '';
  size: number = 0;
  sizeText: string = '';
}
