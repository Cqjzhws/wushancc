// AnimationSpeedTweak v3 — companion dylib for TrollFools / global substrate injection
// Target: iOS 14-17 (arm64), loads into SpringBoard + any host app
// Purpose: Smart-global UI animation acceleration.
//
// 增强（相对 v2）：
//   • 智能缩放：仅压缩 > MinDurationMs 的动画，微动画保留（防残影）
//   • 分类开关：Transitions / Springs / Scroll / Keyboard / Layers 独立启用
//   • 黑名单：指定 bundleID 不加速（游戏/视频）
//   • 按 App 设系数：PerApp 字典覆盖全局系数
//   • 一键关动画：areAnimationsEnabled 模式（最狠）
//   • 强制减弱动态：Reduce Motion（比 hook 更稳）
//   • 覆盖点：UIView 全系 / CATransaction / UIViewPropertyAnimator / UIScrollView /
//            UINavigationController / UITabBarController / UIViewController /
//            CAAnimation 全系 / CALayer 隐式动画 / UIDynamicAnimator
//
// 系数读取：/var/Managed Preferences/mobile/com.developlab.animationspeed.plist
// 编译：theos make package → AnimationSpeedTweak.dylib
// 安装：TrollFools 注入目标 App，或放 /Library/MobileSubstrate/DynamicLibraries/ 全局加载

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>

static double gFactor          = 0.10;   // 全局系数（默认最快）
static double gMinDurationMs   = 150.0;  // 仅压缩长于该值的动画
static BOOL   gInstantMode     = NO;     // YES = 关全部动画
static BOOL   gReduceMotion    = NO;     // YES = 强制减弱动态效果
static BOOL   gCatTransitions  = YES;
static BOOL   gCatSprings      = YES;
static BOOL   gCatScroll       = YES;
static BOOL   gCatKeyboard     = YES;
static BOOL   gCatLayers       = YES;

static NSMutableSet<NSString *>       *gBlacklist;   // bundleID 黑名单
static NSMutableDictionary<NSString*,NSNumber*> *gPerApp;  // bundleID -> factor

static NSString *const kConfigPath = @"/var/Managed Preferences/mobile/com.developlab.animationspeed.plist";
static NSTimeInterval gLastReload = 0;

// MARK: - 配置加载（带节流，避免每次动画都读盘）

static void _reloadConfigIfNeeded(void) {
    NSTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (now - gLastReload < 1.0) return;   // 1s 内不重复读
    gLastReload = now;

    @autoreleasepool {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kConfigPath];
        if (![d isKindOfClass:[NSDictionary class]]) return;

        NSNumber *f = d[@"ViewAnimationFactor"];
        if ([f isKindOfClass:[NSNumber class]] && [f doubleValue] > 0 && [f doubleValue] <= 2.0)
            gFactor = [f doubleValue];

        NSNumber *min = d[@"MinDurationMs"];
        if ([min isKindOfClass:[NSNumber class]] && [min doubleValue] >= 0)
            gMinDurationMs = [min doubleValue];

        NSNumber *inst = d[@"InstantMode"];
        if ([inst isKindOfClass:[NSNumber class]]) gInstantMode = [inst boolValue];

        NSNumber *rm = d[@"ReduceMotion"];
        if ([rm isKindOfClass:[NSNumber class]]) gReduceMotion = [rm boolValue];

        NSDictionary *cat = d[@"Categories"];
        if ([cat isKindOfClass:[NSDictionary class]]) {
            NSNumber *t = cat[@"Transitions"]; if (t) gCatTransitions = [t boolValue];
            NSNumber *s = cat[@"Springs"];     if (s) gCatSprings    = [s boolValue];
            NSNumber *sc= cat[@"Scroll"];      if (sc)gCatScroll     = [sc boolValue];
            NSNumber *k = cat[@"Keyboard"];    if (k) gCatKeyboard   = [k boolValue];
            NSNumber *l = cat[@"Layers"];      if (l) gCatLayers     = [l boolValue];
        }

        NSArray *bl = d[@"Blacklist"];
        if ([bl isKindOfClass:[NSArray class]]) {
            [gBlacklist removeAllObjects];
            for (id x in bl) if ([x isKindOfClass:[NSString class]]) [gBlacklist addObject:x];
        }

        NSDictionary *pa = d[@"PerApp"];
        if ([pa isKindOfClass:[NSDictionary class]]) {
            [gPerApp removeAllObjects];
            for (id k in pa) {
                if (![k isKindOfClass:[NSString class]]) continue;
                id v = pa[k];
                if ([v isKindOfClass:[NSNumber class]]) gPerApp[k] = v;
            }
        }
    }
}

// MARK: - 当前进程的有效系数

static double _effectiveFactor(void) {
    _reloadConfigIfNeeded();
    if (gInstantMode) return 0.0;   // 关动画

    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if (bid && [gBlacklist containsObject:bid]) return 1.0;  // 黑名单不加速

    if (bid) {
        NSNumber *override = gPerApp[bid];
        if (override && [override doubleValue] > 0 && [override doubleValue] <= 2.0)
            return [override doubleValue];
    }
    return gFactor;
}

static inline NSTimeInterval _scaleInterval(NSTimeInterval t, double factor) {
    if (gInstantMode) return 0.0;
    if (t <= 0.0) return t;
    if (t * 1000.0 < gMinDurationMs) return t;   // 微动画保留
    NSTimeInterval s = t * factor;
    return s < 0.01 ? 0.01 : s;
}

static inline CFTimeInterval _scaleCF(CFTimeInterval t, double factor) {
    if (gInstantMode) return 0.0;
    if (t <= 0.0) return t;
    if (t * 1000.0 < gMinDurationMs) return t;
    CFTimeInterval s = t * factor;
    return s < 0.01 ? 0.01 : s;
}

static void _wrapCATransaction(double factor, void (^block)(void)) {
    [CATransaction begin];
    [CATransaction setAnimationDuration:(factor <= 0 ? 0.0 : factor)];
    block();
    [CATransaction commit];
}

// MARK: - 减弱动态效果（Reduce Motion）

%hook UIApplication
- (BOOL)isReduceMotionEnabled { return gReduceMotion ? YES : %orig; }
%end

%hook UIAccessibility
+ (BOOL)isReduceMotionEnabled { return gReduceMotion ? YES : %orig; }
%end

// ====================================================================
// MARK: - UIView.animateWithDuration: 全系（分类：Transitions）
// ====================================================================

%hook UIView

+ (void)animateWithDuration:(NSTimeInterval)duration animations:(void (^)(void))animations {
    double f = _effectiveFactor();
    if (!gCatTransitions) { %orig(duration, animations); return; }
    %orig(_scaleInterval(duration, f), animations);
}

+ (void)animateWithDuration:(NSTimeInterval)duration
                 animations:(void (^)(void))animations
                 completion:(void (^)(BOOL finished))completion {
    double f = _effectiveFactor();
    if (!gCatTransitions) { %orig(duration, animations, completion); return; }
    %orig(_scaleInterval(duration, f), animations, completion);
}

+ (void)animateWithDuration:(NSTimeInterval)duration
                      delay:(NSTimeInterval)delay
                    options:(UIViewAnimationOptions)options
                 animations:(void (^)(void))animations
                 completion:(void (^)(BOOL finished))completion {
    double f = _effectiveFactor();
    if (!gCatTransitions) { %orig(duration, delay, options, animations, completion); return; }
    %orig(_scaleInterval(duration, f), delay * f, options, animations, completion);
}

+ (void)animateWithDuration:(NSTimeInterval)duration
                      delay:(NSTimeInterval)delay
     usingSpringWithDamping:(CGFloat)dampingRatio
      initialSpringVelocity:(CGFloat)velocity
                    options:(UIViewAnimationOptions)options
                 animations:(void (^)(void))animations
                 completion:(void (^)(BOOL finished))completion {
    double f = _effectiveFactor();
    // 弹簧动画归 Springs 分类管
    if (!gCatTransitions && !gCatSprings) { %orig(duration, delay, dampingRatio, velocity, options, animations, completion); return; }
    %orig(_scaleInterval(duration, f), delay * f, dampingRatio, velocity, options, animations, completion);
}

+ (void)transitionWithView:(UIView *)view
                  duration:(NSTimeInterval)duration
                   options:(UIViewAnimationOptions)options
                animations:(void (^)(void))completion
                completion:(void (^)(BOOL finished))completion2 {
    double f = _effectiveFactor();
    if (!gCatTransitions) { %orig(view, duration, options, completion, completion2); return; }
    %orig(view, _scaleInterval(duration, f), options, completion, completion2);
}

+ (void)transitionFromView:(UIView *)fromView
                    toView:(UIView *)toView
                  duration:(NSTimeInterval)duration
                   options:(UIViewAnimationOptions)options
                completion:(void (^)(BOOL finished))completion {
    double f = _effectiveFactor();
    if (!gCatTransitions) { %orig(fromView, toView, duration, options, completion); return; }
    %orig(fromView, toView, _scaleInterval(duration, f), options, completion);
}

// 一键关动画
+ (void)performWithoutAnimation:(void (^)(void))actions {
    if (gInstantMode) { %orig(actions); return; }
    %orig(actions);
}

%end

// ====================================================================
// MARK: - CATransaction
// ====================================================================

%hook CATransaction

+ (void)setAnimationDuration:(CFTimeInterval)duration {
    double f = _effectiveFactor();
    %orig(_scaleCF(duration, f));
}

%end

// ====================================================================
// MARK: - UIViewPropertyAnimator（分类：Springs）
// ====================================================================

%hook UIViewPropertyAnimator

- (instancetype)initWithDuration:(NSTimeInterval)duration
                 timingParameters:(id)parameters {
    double f = _effectiveFactor();
    if (!gCatSprings) return %orig(duration, parameters);
    return %orig(_scaleInterval(duration, f), parameters);
}

- (instancetype)initWithDuration:(NSTimeInterval)duration
                    dampingRatio:(CGFloat)ratio
                      animations:(void (^)(void))animation {
    double f = _effectiveFactor();
    if (!gCatSprings) return %orig(duration, ratio, animation);
    return %orig(_scaleInterval(duration, f), ratio, animation);
}

- (void)setDuration:(NSTimeInterval)duration {
    double f = _effectiveFactor();
    if (!gCatSprings) { %orig(duration); return; }
    %orig(_scaleInterval(duration, f));
}

+ (void)runningPropertyAnimatorWithDuration:(NSTimeInterval)duration
                                      delay:(NSTimeInterval)delay
                                    options:(UIViewAnimationOptions)options
                                 animations:(void (^)(void))animations
                                 completion:(void (^)(UIViewAnimatingPosition finalPosition))completion {
    double f = _effectiveFactor();
    if (!gCatSprings) { %orig(duration, delay, options, animations, completion); return; }
    %orig(_scaleInterval(duration, f), delay * f, options, animations, completion);
}

%end

// ====================================================================
// MARK: - UIScrollView（分类：Scroll）
// ====================================================================

%hook UIScrollView

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated {
    if (!animated || !gCatScroll) { %orig(contentOffset, animated); return; }
    double f = _effectiveFactor();
    _wrapCATransaction(f, ^{ %orig(contentOffset, YES); });
}

- (void)scrollRectToVisible:(CGRect)rect animated:(BOOL)animated {
    if (!animated || !gCatScroll) { %orig(rect, animated); return; }
    double f = _effectiveFactor();
    _wrapCATransaction(f, ^{ %orig(rect, YES); });
}

%end

// ====================================================================
// MARK: - UINavigationController / UITabBarController / UIViewController（分类：Transitions）
// ====================================================================

%hook UINavigationController

- (void)pushViewController:(UIViewController *)vc animated:(BOOL)animated {
    if (!animated || !gCatTransitions) { %orig(vc, animated); return; }
    double f = _effectiveFactor();
    _wrapCATransaction(f, ^{ %orig(vc, YES); });
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated {
    if (!animated || !gCatTransitions) return %orig(animated);
    double f = _effectiveFactor();
    __block UIViewController *ret = nil;
    _wrapCATransaction(f, ^{ ret = %orig(YES); });
    return ret;
}

- (void)setViewControllers:(NSArray<UIViewController *> *)vcs animated:(BOOL)animated {
    if (!animated || !gCatTransitions) { %orig(vcs, animated); return; }
    double f = _effectiveFactor();
    _wrapCATransaction(f, ^{ %orig(vcs, YES); });
}

%end

%hook UITabBarController

- (void)setSelectedIndex:(NSUInteger)idx {
    if (!gCatTransitions) { %orig(idx); return; }
    double f = _effectiveFactor();
    _wrapCATransaction(f, ^{ %orig(idx); });
}

- (void)setSelectedViewController:(UIViewController *)vc {
    if (!gCatTransitions) { %orig(vc); return; }
    double f = _effectiveFactor();
    _wrapCATransaction(f, ^{ %orig(vc); });
}

%end

%hook UIViewController

- (void)presentViewController:(UIViewController *)vc animated:(BOOL)flag completion:(void (^)(void))completion {
    if (!flag || !gCatTransitions) { %orig(vc, flag, completion); return; }
    double f = _effectiveFactor();
    _wrapCATransaction(f, ^{ %orig(vc, YES, completion); });
}

- (void)dismissViewControllerAnimated:(BOOL)flag completion:(void (^)(void))completion {
    if (!flag || !gCatTransitions) { %orig(flag, completion); return; }
    double f = _effectiveFactor();
    _wrapCATransaction(f, ^{ %orig(YES, completion); });
}

%end

// ====================================================================
// MARK: - CAAnimation 全系（含 CALayer 隐式动画）
// ====================================================================

%hook CAAnimation

- (void)setDuration:(CFTimeInterval)duration {
    double f = _effectiveFactor();
    // 弹簧动画归 Springs 分类
    BOOL isSpring = [self isKindOfClass:[CASpringAnimation class]];
    if (isSpring && !gCatSprings) { %orig(duration); return; }
    if (!gCatLayers && ![self isKindOfClass:[CASpringAnimation class]]) {
        // Layers 分类控制隐式动画（非弹簧）
        %orig(duration); return;
    }
    %orig(_scaleCF(duration, f));
}

%end

%hook CABasicAnimation
- (instancetype)init {
    self = %orig;
    if (self) { double f = _effectiveFactor(); self.duration = _scaleCF(self.duration, f); }
    return self;
}
%end

%hook CAKeyframeAnimation
- (instancetype)init {
    self = %orig;
    if (self) { double f = _effectiveFactor(); self.duration = _scaleCF(self.duration, f); }
    return self;
}
%end

%hook CASpringAnimation
- (instancetype)init {
    self = %orig;
    if (self) { double f = _effectiveFactor(); self.duration = _scaleCF(self.duration, f); }
    return self;
}
%end

%hook CATransition
- (instancetype)init {
    self = %orig;
    if (self) { double f = _effectiveFactor(); self.duration = _scaleCF(self.duration, f); }
    return self;
}
%end

// ====================================================================
// MARK: - CALayer 隐式动画（分类：Layers）
// ====================================================================

%hook CALayer

- (id)actionForKey:(NSString *)key {
    id action = %orig;
    if (!gCatLayers) return action;
    if ([action isKindOfClass:[CAAnimation class]]) {
        double f = _effectiveFactor();
        [(CAAnimation *)action setDuration:_scaleCF([(CAAnimation *)action duration], f)];
    }
    return action;
}

%end

// ====================================================================
// MARK: - UIDynamicAnimator（物理动画，尽力关）
// ====================================================================

%hook UIDynamicAnimator

- (void)addBehavior:(UIDynamicBehavior *)behavior {
    // 物理动画无法压时长，但在 InstantMode 下整体禁用动画反馈
    if (gInstantMode) return;
    %orig(behavior);
}

%end

// ====================================================================
// MARK: - 启动
// ====================================================================

%ctor {
    @autoreleasepool {
        gBlacklist = [NSMutableSet set];
        gPerApp    = [NSMutableDictionary dictionary];
        _reloadConfigIfNeeded();
        NSLog(@"[AnimationSpeedTweak] factor=%.3f minMs=%.0f instant=%d reduceMotion=%d",
              gFactor, gMinDurationMs, gInstantMode, gReduceMotion);
    }
}