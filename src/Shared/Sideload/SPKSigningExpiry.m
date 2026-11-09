#import "SPKStrings.h"
#import "SPKSigningExpiry.h"

#import "../UI/SPKNotificationCenter.h"

static NSString *const kSPKSigningExpiryLastNoticeKey = @"spk_signing_expiry_last_notice";
static const NSTimeInterval kSPKSigningExpiryLaunchDelay = 5.0;
static const NSTimeInterval kSPKSigningExpiryWarningInterval = 24.0 * 60.0 * 60.0;

NSDate *SPKSigningExpiryDate(void) {
    static NSDate *expiry;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [NSBundle.mainBundle pathForResource:@"embedded" ofType:@"mobileprovision"];
        NSData *profile = path ? [NSData dataWithContentsOfFile:path] : nil;
        if (profile.length == 0)
            return;
        // The profile is a signed CMS envelope around a plain XML plist. Cut the plist out rather
        // than decoding the envelope: iOS has no public API for that, and only the date is needed.
        NSData *open = [@"<?xml" dataUsingEncoding:NSASCIIStringEncoding];
        NSData *close = [@"</plist>" dataUsingEncoding:NSASCIIStringEncoding];
        NSRange start = [profile rangeOfData:open options:0 range:NSMakeRange(0, profile.length)];
        NSRange end = [profile rangeOfData:close options:NSDataSearchBackwards range:NSMakeRange(0, profile.length)];
        if (start.location == NSNotFound || end.location == NSNotFound || end.location < start.location)
            return;
        NSData *plistData = [profile subdataWithRange:NSMakeRange(start.location, NSMaxRange(end) - start.location)];
        id plist = [NSPropertyListSerialization propertyListWithData:plistData options:NSPropertyListImmutable format:NULL error:NULL];
        id date = [plist isKindOfClass:NSDictionary.class] ? plist[@"ExpirationDate"] : nil;
        if ([date isKindOfClass:NSDate.class])
            expiry = date;
    });
    return expiry;
}

NSString *SPKSigningExpiryRemainingText(void) {
    NSDate *expiry = SPKSigningExpiryDate();
    if (!expiry)
        return nil;
    NSTimeInterval left = expiry.timeIntervalSinceNow;
    if (left <= 0)
        return SPKL(@"SIGNING_EXPIRY_EXPIRED_VALUE");
    NSDateComponentsFormatter *formatter = [NSDateComponentsFormatter new];
    formatter.unitsStyle = NSDateComponentsFormatterUnitsStyleAbbreviated;
    formatter.allowedUnits = left >= 60.0 * 60.0 ? NSCalendarUnitDay | NSCalendarUnitHour : NSCalendarUnitMinute;
    formatter.maximumUnitCount = 2;
    NSString *duration = [formatter stringFromTimeInterval:left] ?: @"";
    return [NSString stringWithFormat:SPKL(@"SIGNING_EXPIRY_TIME_LEFT_VALUE"), duration];
}

NSString *SPKSigningExpiryDateText(void) {
    NSDate *expiry = SPKSigningExpiryDate();
    if (!expiry)
        return nil;
    return [NSDateFormatter localizedStringFromDate:expiry dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
}

void SPKSigningExpiryScheduleLaunchNotice(void) {
    if (!SPKSigningExpiryDate())
        return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSPKSigningExpiryLaunchDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSDate *lastNotice = [defaults objectForKey:kSPKSigningExpiryLastNoticeKey];
        if ([lastNotice isKindOfClass:NSDate.class] && [NSCalendar.currentCalendar isDateInToday:lastNotice])
            return;
        [defaults setObject:NSDate.date forKey:kSPKSigningExpiryLastNoticeKey];

        // The last day gets the warning glyph, so the reinstall is hard to miss.
        BOOL urgent = SPKSigningExpiryDate().timeIntervalSinceNow < kSPKSigningExpiryWarningInterval;
        NSString *title = [NSString stringWithFormat:SPKL(@"SIGNING_EXPIRY_TOAST_TITLE"), SPKSigningExpiryRemainingText()];
        NSString *subtitle = [NSString stringWithFormat:SPKL(@"SIGNING_EXPIRY_TOAST_SUBTITLE"), SPKSigningExpiryDateText()];
        SPKNotify(kSPKNotificationSigningExpiry, title, subtitle, urgent ? @"warning_filled" : @"history", SPKNotificationToneInfo);
    });
}
