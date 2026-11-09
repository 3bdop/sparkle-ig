//  SPKSigningExpiry.h
//  Tells a sideloaded install how long it has before iOS stops opening it.
//
//  Sideloading tools embed the provisioning profile they signed with as embedded.mobileprovision.
//  Its ExpirationDate is when the app stops launching: seven days after signing for a free Apple
//  ID. App Store and jailbreak installs have no profile, and every function here returns nil.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The profile's expiration date, read once per launch.
FOUNDATION_EXPORT NSDate *_Nullable SPKSigningExpiryDate(void);

/// "6d 23h left", "5h left" or "Expired".
FOUNDATION_EXPORT NSString *_Nullable SPKSigningExpiryRemainingText(void);

/// The expiration as a medium date and short time in the current locale.
FOUNDATION_EXPORT NSString *_Nullable SPKSigningExpiryDateText(void);

/// Call once per launch. Once launch settles, shows the time left as a toast, at most once a day.
FOUNDATION_EXPORT void SPKSigningExpiryScheduleLaunchNotice(void);

NS_ASSUME_NONNULL_END
