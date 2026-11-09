#import "SPKStrings.h"
#import "TweakSettings.h"

#import "../Shared/Sideload/SPKSigningExpiry.h"
#import "SPKTopicSettingsSupport.h"

#import "Topics/SPKAboutSettingsProvider.h"
#import "Topics/SPKDataSettingsProvider.h"
#import "Topics/SPKDownloadsSettingsProvider.h"
#import "Topics/SPKFeedSettingsProvider.h"
#import "Topics/SPKGallerySettingsProvider.h"
#import "Topics/SPKGeneralSettingsProvider.h"
#import "Topics/SPKInstantsSettingsProvider.h"
#import "Topics/SPKInterfaceSettingsProvider.h"
#import "Topics/SPKMessagesSettingsProvider.h"
#import "Topics/SPKProfileAnalyzerSettingsProvider.h"
#import "Topics/SPKProfileSettingsProvider.h"
#import "Topics/SPKReelsSettingsProvider.h"
#import "Topics/SPKStoriesSettingsProvider.h"
#import "Topics/SPKToolsSettingsProvider.h"

@implementation SPKTweakSettings

/// Sideloaded installs only: how long until the signing expires and the IPA has to be reinstalled.
static NSArray *SPKSigningExpirySections(void) {
    NSString *remaining = SPKSigningExpiryRemainingText();
    if (!remaining)
        return @[];
    NSString *subtitle = [NSString stringWithFormat:@"%@ · %@", remaining, SPKSigningExpiryDateText()]; // SPK_I18N_IGNORE: separator
    return @[ @{
        @"header" : @"",
        @"rows" : @[
            SPKSettingWithHelp([SPKSetting staticCellWithTitle:SPKL(@"SIGNING_EXPIRY_TITLE")
                                                      subtitle:subtitle
                                                          icon:SPKSettingsIcon(@"history")],
                               SPKL(@"SIGNING_EXPIRY_HELP"))
        ]
    } ];
}

+ (NSArray *)sections {
    return [SPKSigningExpirySections() arrayByAddingObjectsFromArray:@[
        @{
            @"header" : @"",
            @"rows" : @[
                [SPKGeneralSettingsProvider rootSetting],
                [SPKInterfaceSettingsProvider rootSetting],
                [SPKFeedSettingsProvider rootSetting],
                [SPKStoriesSettingsProvider rootSetting],
                [SPKReelsSettingsProvider rootSetting],
                [SPKMessagesSettingsProvider rootSetting],
                [SPKInstantsSettingsProvider rootSetting],
                [SPKProfileSettingsProvider rootSetting]
            ]
        },
        @{
            @"header" : @"",
            @"rows" : @[
                [SPKGallerySettingsProvider rootSetting],
                [SPKDownloadsSettingsProvider rootSetting],
                [SPKProfileAnalyzerSettingsProvider rootSetting]
            ]
        },
        @{
            @"header" : @"",
            @"rows" : @[
                [SPKToolsSettingsProvider rootSetting],
                [SPKDataSettingsProvider rootSetting]
            ]
        },
        @{
            @"header" : @"",
            @"rows" : @[
                [SPKAboutSettingsProvider rootSetting]
            ]
        }
    ]];
}

+ (NSString *)title {
    return SPKL(@"ABOUT_INFORMATION_SPARKLE_TITLE");
}

@end
