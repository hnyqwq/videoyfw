# 云影工具屋 YunYing Tool House

云影工具屋是一款HarmonyOS视频播放器，支持输入链接播放网络视频，也可选择本地视频。内置网页视频提取功能，一键识别网页中的视频资源；支持"碰一碰"和"隔空传送"分享视频或视频链接；还有扫码输入、OCR文字识别、跨设备接续等便捷功能，适配鸿蒙多端设备。

HarmonyOS APP ๑>ᴗO๑ —— by hnyqwq

## 使用说明

1. **安装**
    - 在 HarmonyOS 5 及以上系统的手机/平板/电脑的应用市场中搜索“云影工具屋”或通过以下链接下载安装：
      [应用市场链接](https://appgallery.huawei.com/app/detail?id=com.hny.video)
    - 体验新版本，加入邀请测试链接：[AppTest邀请链接](https://appgallery.huawei.com/apptest/52fRvA7p5Ow)

2. **启动应用**
    - 安装完成后，点击桌面图标启动应用。

3. **功能操作**
    - 主界面提供卡片式导航，点击相应功能进入对应页面。
    - 根据页面提示操作即可完成所需任务。

## 项目结构

- `entry/`：主模块目录，包含应用的主要代码和资源文件。
    - `src/main/ets/`：主要源码目录，包含多个功能模块的实现。
    - `resources/`：资源文件目录，包含图片、字符串、配置文件等。
- `AppScope/`：应用全局配置文件和资源目录。
- `hvigor/`：构建配置目录。

## 开发与构建

- 项目基于 HarmonyOS SDK 开发，使用 ArkTS 编写。
- 使用 HVIGOR 构建工具进行项目构建。
