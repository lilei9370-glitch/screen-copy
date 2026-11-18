# 框选取字

在 Mac 上拖框选中屏幕文字，松手就识别并复制。支持简体中文、繁体中文和英文，使用 macOS 内置的 Vision 离线识别。

## 安装和使用

[下载框选取字 1.0（DMG）](https://github.com/lilei9370-glitch/screen-copy/releases/download/v1.0/ScreenCopy-1.0-macOS-arm64.dmg) · [查看发布页](https://github.com/lilei9370-glitch/screen-copy/releases/tag/v1.0)

- 支持搭载 Apple 芯片、运行 macOS 15 或更新版本的 Mac。
- 打开 DMG，把「框选取字」拖到窗口里的「应用程序」。从「应用程序」打开 App，首次按指引在「系统设置 → 隐私与安全性 → 录屏与系统录音」允许录屏。
- 默认快捷键是 **Control + Shift + Command + D**。点菜单栏图标里的「设置软件快捷键…」可以更改。
- 拖框并松手后用 **⌘V** 粘贴。右键单击或按 **Esc** 取消。
- 默认只在 App 打开时响应快捷键。想在退出后也能用，在菜单里开启「关闭后也能用快捷键」。如果系统要求确认，在「系统设置 → 通用 → 登录项与扩展」允许后台运行。开启后，监听器在登录时启动，App 会在第一次取字时打开并留在菜单栏。
- 卸载前如果启用了「关闭后也能用快捷键」，先在菜单里关闭，再退出 App 并把它移到废纸篓。

App 只在选区确定后截取框内画面。图片仅在取字进程的内存中处理，识别后进程退出。剪贴板收到的是文字。

下载包使用本地临时签名，未经过 Apple 公证。如果首次打开时 macOS 提示无法验证开发者，请确认下载来源，再参照 [Apple 官方打开说明](https://support.apple.com/zh-cn/102445)。

## 本地构建和打包

使用 Xcode Command Line Tools（`xcode-select --install`）。

```sh
./build.sh
open "dist/框选取字.app"
ditto -c -k --keepParent "dist/框选取字.app" "dist/ScreenCopy-1.0-macOS-arm64.zip"
```

默认构建使用本地临时签名，供本机测试。正式分发时使用 `CODE_SIGN_IDENTITY="Developer ID Application: …" ./build.sh`，完成 Apple 公证并装订后再打包。 [Apple 公证指引](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)

源码采用 [MIT 许可证](LICENSE)。
