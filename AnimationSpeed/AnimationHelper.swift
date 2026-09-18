import Foundation

// 多个动画加速点（v3）
let uIKitPlistPath = "/var/Managed Preferences/mobile/com.apple.UIKit.plist"
let speedConfigPlistPath = "/var/Managed Preferences/mobile/com.developlab.animationspeed.plist"

// MARK: - 预设档位（默认最快）

enum SpeedPreset: Int, CaseIterable {
    case fastest = 0
    case fast    = 1
    case normal  = 2
    case slow    = 3

    var displayName: String {
        switch self {
        case .fastest: return "最快 (推荐)"
        case .fast:    return "快"
        case .normal:  return "正常"
        case .slow:    return "慢"
        }
    }

    var dragCoefficient: Double {
        switch self {
        case .fastest: return 0.001
        case .fast:    return 0.05
        case .normal:  return 1.00
        case .slow:    return 2.00
        }
    }

    var viewAnimationFactor: Double {
        switch self {
        case .fastest: return 0.10
        case .fast:    return 0.50
        case .normal:  return 1.00
        case .slow:    return 1.50
        }
    }
}

// MARK: - 主配置结构

struct SpeedConfig {
    var factor: Double          = 0.10    // ViewAnimationFactor，全局系数
    var minDurationMs: Double   = 150.0   // 仅压缩长于该值的动画
    var instantMode: Bool       = false   // 一键关动画
    var reduceMotion: Bool      = false   // 强制减弱动态
    var categories: [String: Bool] = [
        "Transitions": true,
        "Springs":     true,
        "Scroll":      true,
        "Keyboard":    true,
        "Layers":      true
    ]
    var blacklist: [String]     = []      // 不加速的 bundleID
    var perApp: [String: Double] = [:]    // bundleID -> factor 覆盖

    static let `default` = SpeedConfig()

    func toDict() -> [String: Any] {
        return [
            "Version": AnimationHelper.currentVersion,
            "ViewAnimationFactor": factor,
            "MinDurationMs": minDurationMs,
            "InstantMode": instantMode,
            "ReduceMotion": reduceMotion,
            "Categories": categories,
            "Blacklist": blacklist,
            "PerApp": perApp
        ]
    }
}

// MARK: - 主逻辑

class AnimationHelper {

    static let currentVersion = "3.0.0"
    static let defaultPreset: SpeedPreset = .fastest

    // 权限
    static func checkInstallPermission() -> Bool {
        let path = "/var/mobile/Library/Preferences"
        return access(path, W_OK) == 0
    }

    // 读当前配置
    static func currentConfig() -> SpeedConfig {
        guard let dict = NSDictionary(contentsOfFile: speedConfigPlistPath) as? [String: Any] else {
            return SpeedConfig.default
        }
        var c = SpeedConfig.default
        if let f = dict["ViewAnimationFactor"] as? Double { c.factor = f }
        if let m = dict["MinDurationMs"] as? Double { c.minDurationMs = m }
        if let i = dict["InstantMode"] as? Bool { c.instantMode = i }
        if let r = dict["ReduceMotion"] as? Bool { c.reduceMotion = r }
        if let cat = dict["Categories"] as? [String: Bool] { c.categories = cat }
        if let bl = dict["Blacklist"] as? [String] { c.blacklist = bl }
        if let pa = dict["PerApp"] as? [String: Double] { c.perApp = pa }
        return c
    }

    // 写配置（同时写 UIKit plist 的拖动系数，供未注入 dylib 时也有基础效果）
    @discardableResult
    static func write(config: SpeedConfig) -> Bool {
        // 1) 共享配置（dylib 读取）
        let ok1 = (config.toDict() as NSDictionary).write(toFile: speedConfigPlistPath, atomically: true)

        // 2) UIKit 主 plist（拖动系数，兼容无 dylib 场景）
        ensureUIKitPlistExists()
        var dict = (NSDictionary(contentsOfFile: uIKitPlistPath) as? [String: Any]) ?? [:]
        dict["UIAnimationDragCoefficient"] = config.factor <= 0 ? 0.001 : max(0.001, config.factor)
        dict["UIScrollViewDecelerationRate"] = config.factor <= 0 ? 0.999 : 0.998
        let ok2 = (dict as NSDictionary).write(toFile: uIKitPlistPath, atomically: true)

        return ok1 && ok2
    }

    // 应用预设
    @discardableResult
    static func apply(preset: SpeedPreset) -> Bool {
        var c = currentConfig()
        c.factor = preset.viewAnimationFactor
        c.instantMode = false
        c.reduceMotion = false
        return write(config: c)
    }

    static func ensureUIKitPlistExists() {
        let fm = FileManager.default
        let dir = "/var/Managed Preferences/mobile"
        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: uIKitPlistPath) {
            let empty: [String: Any] = [:]
            (empty as NSDictionary).write(toFile: uIKitPlistPath, atomically: true)
        }
    }

    // 恢复默认
    static func restoreDefault() -> Bool {
        let fm = FileManager.default
        var ok = true
        if fm.fileExists(atPath: uIKitPlistPath) {
            do { try fm.removeItem(atPath: uIKitPlistPath) } catch { ok = false }
        }
        if fm.fileExists(atPath: speedConfigPlistPath) {
            do { try fm.removeItem(atPath: speedConfigPlistPath) } catch { ok = false }
        }
        return ok
    }

    // 当前 App 的 bundleID（用于示例）
    static func currentBundleID() -> String {
        return Bundle.main.bundleIdentifier ?? "unknown"
    }
}