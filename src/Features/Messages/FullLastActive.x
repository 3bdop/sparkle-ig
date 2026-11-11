// Full Last Active — rewrites the chat header presence subtitle
// ("Active 2h ago") into an absolute timestamp ("Active at 1:15 AM").
//
// Instagram already delivers the recipient's exact last-active date to the
// client (the header title view's backing view model carries `lastActiveTime`);
// it just renders it as a relative string. We pull that date out and re-render
// the subtitle. No extra tracking — only the label Instagram already shows is
// reformatted.
//
// Controlled by a single tri-state pref `msgs_last_active_format`:
//   "off"      — feature disabled (hooks not installed)
//   "smart"    — time alone for today, adds the date for older days
//   "datetime" — always shows the date and time
//
// Reciprocity note: this only surfaces presence that Instagram is already
// sending. When your own activity status is off, the server withholds others'
// presence entirely, so there is nothing to reformat — that tie is enforced
// server-side and cannot be undone from the client.

#import "../../InstagramHeaders.h"
#import "SPKStrings.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import "../../App/SPKPerfMeter.h"

// Instagram's presence "Active now" window. Inside it we leave IG's own string
// alone so the live indicator keeps reading "Active now".
static const NSTimeInterval kSPKActiveNowWindow = 300.0;

// The feature is on whenever the format pref is anything other than "off".
static BOOL SPKLastActiveEnabled(void) {
    NSString *style = [SPKUtils getStringPref:@"msgs_last_active_format"] ?: @"off";
    return ![style isEqualToString:@"off"];
}

// Builds a locale-aware absolute timestamp and wraps it in the localized
// "Last active" status. Date order, punctuation and hour cycle come from the
// active Sparkle language rather than English source literals.
static NSString *SPKFormattedLastActive(NSDate *date) {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *now = [NSDate date];
    BOOL sameDay = [cal isDate:date inSameDayAsDate:now];
    BOOL sameYear = [cal component:NSCalendarUnitYear fromDate:date] ==
                    [cal component:NSCalendarUnitYear fromDate:now];

    NSString *style = [SPKUtils getStringPref:@"msgs_last_active_format"] ?: @"smart";
    NSString *body = nil;
    if ([style isEqualToString:@"smart"] && sameDay) {
        body = [SPKUtils spk_formattedTime:date];
    } else {
        body = [SPKUtils spk_formattedDateTime:date includingYear:!sameYear];
    }
    if (!body.length)
        return nil;
    return [NSString stringWithFormat:SPKL(@"MESSAGES_LAST_ACTIVE_STATUS_FORMAT"), body];
}

// Digs the recipient's last-active date out of the title view. Primary path
// mirrors IG's own wiring (delegate → state provider → thread view model);
// fallbacks probe the title view's own models. All KVC, all guarded — a miss
// just no-ops the feature on that build.
static NSDate *SPKCoerceDate(id value) {
    if ([value isKindOfClass:[NSDate class]])
        return value;
    if ([value isKindOfClass:[NSNumber class]]) {
        double t = [value doubleValue];
        if (t > 1e12)
            t /= 1000.0;  // milliseconds → seconds
        if (t > 1e6)
            return [NSDate dateWithTimeIntervalSince1970:t];
    }
    return nil;
}

static NSDate *SPKValueForKeyPathSafely(id object, NSString *key) {
    if (!object)
        return nil;
    @try {
        return SPKCoerceDate([object valueForKey:key]);
    } @catch (__unused NSException *e) {
    }
    return nil;
}

static NSDate *SPKLastActiveDateForTitleView(IGDirectLeftAlignedTitleView *titleView) {
    // Path 1: delegate's state provider view model (IG's own source of truth).
    if ([titleView respondsToSelector:@selector(delegate)]) {
        id delegate = [titleView delegate];
        if (delegate) {
            Ivar spIvar = class_getInstanceVariable([delegate class], "_stateProvider");
            if (spIvar) {
                id stateProvider = object_getIvar(delegate, spIvar);
                SEL vmSel = NSSelectorFromString(@"viewModel");
                if ([stateProvider respondsToSelector:vmSel]) {
                    id viewModel = ((id (*)(id, SEL))objc_msgSend)(stateProvider, vmSel);
                    NSDate *date = SPKValueForKeyPathSafely(viewModel, @"lastActiveTime");
                    if (date)
                        return date;
                }
            }
        }
    }

    // Path 2/3: the title view's own models sometimes carry the date directly.
    NSDate *date = SPKValueForKeyPathSafely(titleView.titleViewModel, @"lastActiveTime");
    if (date)
        return date;
    if ([titleView respondsToSelector:@selector(_currentSubtitleViewModel)])
        date = SPKValueForKeyPathSafely([titleView _currentSubtitleViewModel], @"lastActiveTime");
    return date;
}

// Given the presence string IG produced and the recipient's last-active date,
// builds the "Active at ..." replacement while preserving IG's styling. Returns
// nil (leave IG's string) inside the "Active now" window, when there's nothing
// to format, or when the result would be identical.
static NSAttributedString *SPKFormattedPresenceAttributedString(NSAttributedString *orig, NSDate *date) {
    if (!date)
        return nil;
    // Within IG's presence window — let it keep rendering "Active now".
    if ([[NSDate date] timeIntervalSinceDate:date] < kSPKActiveNowWindow)
        return nil;

    NSString *formatted = SPKFormattedLastActive(date);
    if (!formatted.length)
        return nil;

    // Preserve IG's styling (font/color) so it stays native.
    NSDictionary *attrs = orig.length > 0 ? [orig attributesAtIndex:0 effectiveRange:NULL] : nil;
    NSAttributedString *replacement = [[NSAttributedString alloc] initWithString:formatted attributes:attrs];
    if ([replacement isEqualToAttributedString:orig])
        return nil;
    return replacement;
}

// IG's own relative string ("Active 14h ago") from before the rewrite, kept per title view
// so labels that still show it can be found after the model already carries ours.
static const void *kSPKLastActiveOriginalTextKey = &kSPKLastActiveOriginalTextKey;

// Logs each distinct state once, so layout passes don't flood the log. Read with
// `pymobiledevice3 syslog live` and look for "[Sparkle LastActive]".
static void SPKLastActiveTrace(NSString *message) {
    static NSString *lastMessage;
    if ([message isEqualToString:lastMessage])
        return;
    lastMessage = [message copy];
    SPKLog(@"LastActive", @"%@", message);
}

static void SPKCollectViews(UIView *view, NSMutableArray<UILabel *> *labels, NSMutableArray<NSString *> *leafClasses) {
    if ([view isKindOfClass:[UILabel class]])
        [labels addObject:(UILabel *)view];
    else if (view.subviews.count == 0)
        [leafClasses addObject:NSStringFromClass([view class])];
    for (UIView *subview in view.subviews)
        SPKCollectViews(subview, labels, leafClasses);
}

static void SPKRewriteLastActiveSubtitle(IGDirectLeftAlignedTitleView *titleView) {
    if (!SPKLastActiveEnabled())
        return;
    if (![titleView respondsToSelector:@selector(_currentSubtitleViewModel)]) {
        SPKLastActiveTrace(@"title view has no _currentSubtitleViewModel");
        return;
    }

    id subtitle = [titleView _currentSubtitleViewModel];
    NSDate *date = SPKLastActiveDateForTitleView(titleView);
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    NSMutableArray<NSString *> *leafClasses = [NSMutableArray array];
    SPKCollectViews(titleView, labels, leafClasses);
    NSMutableArray<NSString *> *labelDescriptions = [NSMutableArray array];
    for (UILabel *label in labels)
        [labelDescriptions addObject:[NSString stringWithFormat:@"%@ '%@'", NSStringFromClass([label class]), label.text ?: @""]];
    SPKLastActiveTrace([NSString stringWithFormat:@"subtitle=%@ date=%@ labels=[%@] other=[%@]",
                                                  subtitle ? NSStringFromClass([subtitle class]) : @"nil",
                                                  date ?: @"nil",
                                                  [labelDescriptions componentsJoinedByString:@", "],
                                                  [leafClasses componentsJoinedByString:@", "]]);
    if (!subtitle || !date)
        return;

    @try {
        id current = [subtitle valueForKey:@"text"];
        if (![current isKindOfClass:[NSAttributedString class]]) {
            SPKLastActiveTrace([NSString stringWithFormat:@"subtitle text is %@", current ? NSStringFromClass([current class]) : @"nil"]);
            return;
        }
        NSAttributedString *replacement = SPKFormattedPresenceAttributedString(current, date);
        if (replacement) {
            objc_setAssociatedObject(titleView, kSPKLastActiveOriginalTextKey, [current string], OBJC_ASSOCIATION_COPY_NONATOMIC);
            [subtitle setValue:replacement forKey:@"text"];
        } else {
            // nil both inside the "Active now" window and once the model already carries our
            // text; only the latter can still have labels left to catch up.
            if (![[current string] isEqualToString:SPKFormattedLastActive(date)])
                return;
            replacement = current;
        }

        // IG reads the subtitle text once before our overwrite lands, so mirror
        // it straight onto the label too.
        Ivar labelIvar = class_getInstanceVariable([titleView class], "_subtitleLabel");
        if (labelIvar) {
            UILabel *label = object_getIvar(titleView, labelIvar);
            if ([label isKindOfClass:[UILabel class]])
                label.attributedText = replacement;
        }

        // IG 454 can draw the subtitle in subtitle views of its own rather than _subtitleLabel,
        // so replace IG's string wherever a label in the header still shows it.
        NSString *original = objc_getAssociatedObject(titleView, kSPKLastActiveOriginalTextKey);
        NSUInteger replaced = 0;
        for (UILabel *label in labels) {
            if (original.length > 0 && [label.text isEqualToString:original]) {
                label.attributedText = replacement;
                replaced++;
            }
        }
        SPKLastActiveTrace([NSString stringWithFormat:@"rewrote '%@' -> '%@', %lu other label(s)", original ?: @"", [replacement string], (unsigned long)replaced]);
    } @catch (NSException *e) {
        SPKLastActiveTrace([NSString stringWithFormat:@"exception: %@", e.reason]);
    }
}

%group SPKFullLastActiveHooks

%hook IGDirectLeftAlignedTitleView

- (void)setTitleViewModel:(id)titleViewModel {
    %orig;
    SPKRewriteLastActiveSubtitle(self);
}

- (void)animationCoordinatorDidUpdate:(id)coordinator {
    %orig;
    SPKRewriteLastActiveSubtitle(self);
}

- (void)layoutSubviews {
    %orig;
    SPK_PERF_SCOPE(@"FullLastActive.layoutSubviews");
    SPKRewriteLastActiveSubtitle(self);
}

%end

%end

void SPKInstallFullLastActiveHooksIfEnabled(void) {
    if (!SPKLastActiveEnabled())
        return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKFullLastActiveHooks);
    });
}
