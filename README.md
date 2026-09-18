# AnimationSpeed v3 + Companion dylib (全局增强版)

基于 DevelopCubeLab/AnimationSpeed（Apache-2.0）深度增强。

## 相对 1.0.1 / v2 的增强

| 能力 | 1.0.1 | v2 | v3（本版） |
|------|-------|-----|-----------|
| 加速键 | 1（拖动） | 2 | 2 + dylib 全系 hook |
| 预设 | 文本框 | 4 档 | 4 档 + 自定义滑块 |
| 默认档 | 1.0 | 最快 0.05 | **最快 0.001 / ×0.10** |
| 智能缩放 | ✗ | ✗ | ✓ 仅压 >MinDurationMs 的长动画 |
| 分类开关 | ✗ | ✗ | ✓ 转场/弹簧/滚动/键盘/图层 |
| 黑名单 | ✗ | ✗ | ✓ 按 bundleID 排除 |
| 按 App 设系数 | ✗ | ✗ | ✓ PerApp 字典 |
| 瞬间模式 | ✗ | ✗ | ✓ 一键关全部动画 |
| 减弱动态 | ✗ | ✗ | ✓ 强制 Reduce Motion |
| 实时 FPS | ✗ | ✗ | ✓ |
| 全局覆盖 | ✗ | SpringBoard | ✓ 通配 filter 加载所有进程 |

## 文件

- `AnimationSpeed/` — App 源码（Swift + ObjC，theos xcodeproj）
- `Tweak/` — 配套 dylib（Logos Tweak.xm）+ 全局 filter plist
- `.github/workflows/build.yml` — GitHub Actions 自动构建（macOS runner）
- `Makefile` / `control` / `entitlements.plist` — 工程文件

## 编译

GitHub Actions：
1. 推送到 GitHub 仓库
2. Actions → "Build AnimationSpeed v3 + Tweak dylib" → Run workflow
3. 下载 artifact `AnimationSpeed-v3-build`
   - `AnimationSpeed_3.0.0.tipa` — TrollStore 安装
   - `AnimationSpeedTweak.dylib` — TrollFools 注入 / 或随 deb 全局安装

## 使用

**基础（仅 App）**：TrollStore 装 TIPA → 选预设/拖滑块 → 应用 → 注销。仅影响拖动系数。

**全局（dylib）**：
- 方式 A（TrollFools）：注入目标 App（或 SpringBoard）→ Respring
- 方式 B（系统级）：把 dylib + filter plist 放到 `/Library/MobileSubstrate/DynamicLibraries/`，经 TrollStore 的 MobileSubstrate 加载进所有进程（一次注入全 App 覆盖）

注入后所有动画（开 App、切页面、present、滚动、弹簧…）统一按配置系数加速。App 端调节实时生效（dylib 每秒读一次配置）。

## dylib 覆盖的 hook 点

- UIView.animateWithDuration: 全 6 变体 + transition*
- CATransaction.setAnimationDuration:
- UIViewPropertyAnimator（init 系列 + setDuration: + runningPropertyAnimator）
- UIScrollView setContentOffset / scrollRectToVisible
- UINavigationController push/pop/setViewControllers
- UITabBarController setSelectedIndex/setSelectedViewController
- UIViewController present/dismiss
- CAAnimation 全系（Basic/Keyframe/Spring/Transition）+ CALayer 隐式动画
- UIDynamicAnimator（瞬间模式下降级）
- UIApplication/UIAccessibility 减弱动态

## 配置 plist 结构

`/var/Managed Preferences/mobile/com.developlab.animationspeed.plist`

```plist
ViewAnimationFactor: 0.10     // 全局系数
MinDurationMs: 150            // 仅压更长的动画
InstantMode: false            // 一键关动画
ReduceMotion: false           // 强制减弱动态
Categories: { Transitions, Springs, Scroll, Keyboard, Layers: true }
Blacklist: [ "com.example.game" ]   // 不加速
PerApp: { "com.example.app": 0.05 } // 单 App 覆盖
```

## 协议

Apache-2.0，归属 DevelopCubeLab 原作者。
