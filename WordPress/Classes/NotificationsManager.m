/*
 * NotificationsManager.m
 *
 * Copyright (c) 2013 WordPress. All rights reserved.
 *
 * Licensed under GNU General Public License 2.0.
 * Some rights reserved. See license.txt
 */

#import <Helpshift/Helpshift.h>
#import "NotificationsManager.h"
#import "Note.h"
#import "WordPressAppDelegate.h"
#import "WPAccount.h"
#import "WordPressComApi.h"
#import "UIDevice+WordPressIdentifier.h"
#import <WPXMLRPCClient.h>
#import "ContextManager.h"

static NSString *const NotificationsPreferencesKey = @"notification_preferences";
NSString *const NotificationsDeviceToken = @"apnsDeviceToken";

@implementation NotificationsManager

+ (void)registerForPushNotifications {
#if TARGET_IPHONE_SIMULATOR
    return;
#endif
    [[UIApplication sharedApplication]
     registerForRemoteNotificationTypes:(UIRemoteNotificationTypeBadge |
                                         UIRemoteNotificationTypeSound |
                                         UIRemoteNotificationTypeAlert)];
}


#pragma mark - Device token registration

+ (void)registerDeviceToken:(NSData *)deviceToken {
    // We want to register Helpshift regardless so that way if a user isn't logged in
    // they can still get push notifications that we replied to their support ticket.
    [[Helpshift sharedInstance] registerDeviceToken:deviceToken];

    // Don't bother registering for WordPress anything if the user isn't logged in
    if (![WPAccount defaultWordPressComAccount])
        return;

    NSString *newToken = [[[[deviceToken description]
                           stringByReplacingOccurrencesOfString: @"<" withString: @""]
                          stringByReplacingOccurrencesOfString: @">" withString: @""]
                         stringByReplacingOccurrencesOfString: @" " withString: @""];
    
    DDLogInfo(@"Device token received in didRegisterForRemoteNotificationsWithDeviceToken: %@", newToken);
    
    // Store the token
    NSString *previousToken = [[NSUserDefaults standardUserDefaults] objectForKey:NotificationsDeviceToken];
    if (![previousToken isEqualToString:newToken]) {
        DDLogInfo(@"Device Token has changed! OLD Value %@, NEW value %@", previousToken, newToken);
        [[NSUserDefaults standardUserDefaults] setObject:newToken forKey:NotificationsDeviceToken];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    [self syncPushNotificationInfo];
}

+ (void)registrationDidFail:(NSError *)error {
    DDLogError(@"Failed to register for push notifications: %@", error);
    [self unregisterDeviceToken];
}

+ (void)unregisterDeviceToken {
    NSString *token = [[NSUserDefaults standardUserDefaults] objectForKey:NotificationsDeviceToken];
    [[[WPAccount defaultWordPressComAccount] restApi] unregisterForPushNotificationsWithDeviceToken:token success:^{
        DDLogInfo(@"Unregistered push token %@", token);

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults removeObjectForKey:NotificationsDeviceToken];
        [defaults removeObjectForKey:NotificationsPreferencesKey];
        [defaults synchronize];
    } failure:^(NSError *error){
        DDLogError(@"Couldn't unregister push token: %@", [error localizedDescription]);
    }];
}

+ (BOOL)deviceRegisteredForPushNotifications {
    return [[NSUserDefaults standardUserDefaults] objectForKey:NotificationsDeviceToken] != nil;
}

#pragma mark - Notification handling

+ (void)handleNotification:(NSDictionary *)userInfo forState:(UIApplicationState)state completionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    DDLogVerbose(@"Received push notification:\nPayload: %@\nCurrent Application state: %d", userInfo, state);
    
    if ([[userInfo objectForKey:@"origin"] isEqualToString:@"helpshift"]) {
        [[Helpshift sharedInstance] handleRemoteNotification:userInfo withController:[[UIApplication sharedApplication] keyWindow].rootViewController];
        return;
    }
    
    if ([userInfo stringForKey:@"type"]) { //check if it is the badge reset PN
        NSString *notificationType = [userInfo stringForKey:@"type"];
        if ([notificationType isEqualToString:@"badge-reset"]) {
            [UIApplication sharedApplication].applicationIconBadgeNumber = 0;
            //Try to pull the badge number from the notification object
            NSDictionary *apsObject = [userInfo dictionaryForKey:@"aps"];
            if (apsObject) {
                NSNumber *badgeCount = [apsObject numberForKey:@"badge"];
                if (badgeCount) {
                    [UIApplication sharedApplication].applicationIconBadgeNumber = [badgeCount intValue];
                }
            }
            return;
        }
    }
    
    switch (state) {
        case UIApplicationStateActive:
            [[WordPressAppDelegate sharedWordPressApplicationDelegate] clearBadgeAndSyncItemsIfNotificationsScreenActive];
            break;
            
        case UIApplicationStateInactive:
            [WPMobileStats recordAppOpenedForEvent:StatsEventAppOpenedDueToPushNotification];
            [[WordPressAppDelegate sharedWordPressApplicationDelegate] showNotificationsTab];
            break;
            
        case UIApplicationStateBackground:
            if (completionHandler) {
                [Note fetchNewNotificationsWithSuccess:^(BOOL hasNewNotes) {
                    DDLogVerbose(@"notification fetch completion handler completed with new notes: %@", hasNewNotes ? @"YES" : @"NO");
                    if (hasNewNotes) {
                        completionHandler(UIBackgroundFetchResultNewData);
                    } else {
                        completionHandler(UIBackgroundFetchResultNoData);
                    }
                } failure:^(NSError *error) {
                    DDLogError(@"notification fetch completion handler failed with error: %@", error);
                    completionHandler(UIBackgroundFetchResultFailed);
                }];
            }
            break;
        default:
            break;
    }
}

+ (void)handleNotificationForApplicationLaunch:(NSDictionary *)launchOptions {
    NSDictionary *remoteNotif = [launchOptions objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    if (remoteNotif) {
        [WPMobileStats recordAppOpenedForEvent:StatsEventAppOpenedDueToPushNotification];
        
        DDLogVerbose(@"Launched with a remote notification as parameter:  %@", remoteNotif);
        [[WordPressAppDelegate sharedWordPressApplicationDelegate] showNotificationsTab];
    }
}


#pragma mark - WordPress.com XML RPC API

+ (NSDictionary *)notificationSettingsDictionary {
    if (![[[WPAccount defaultWordPressComAccount] restApi] hasCredentials]) {
        return nil;
    }
    
    NSDictionary *notificationPreferences = [[NSUserDefaults standardUserDefaults] objectForKey:NotificationsPreferencesKey];
    if (!notificationPreferences)
        return nil;
    
    NSMutableArray *notificationPrefArray = [[notificationPreferences allKeys] mutableCopy];
    if ([notificationPrefArray indexOfObject:@"muted_blogs"] != NSNotFound) {
        [notificationPrefArray removeObjectAtIndex:[notificationPrefArray indexOfObject:@"muted_blogs"]];
    }
    
    // Build the dictionary to send in the API call
    NSMutableDictionary *updatedSettings = [[NSMutableDictionary alloc] init];
    for (int i = 0; i < [notificationPrefArray count]; i++) {
        NSDictionary *updatedSetting = [notificationPreferences objectForKey:[notificationPrefArray objectAtIndex:i]];
        [updatedSettings setValue:[updatedSetting objectForKey:@"value"] forKey:[notificationPrefArray objectAtIndex:i]];
    }
    
    //Check and send 'mute_until' value
    NSMutableDictionary *muteDictionary = [notificationPreferences objectForKey:@"mute_until"];
    if(muteDictionary != nil  && [muteDictionary objectForKey:@"value"] != nil) {
        [updatedSettings setValue:[muteDictionary objectForKey:@"value"] forKey:@"mute_until"];
    } else {
        [updatedSettings setValue:@"0" forKey:@"mute_until"];
    }
    
    NSArray *blogsArray = [[notificationPreferences objectForKey:@"muted_blogs"] objectForKey:@"value"];
    NSMutableArray *mutedBlogsArray = [[NSMutableArray alloc] init];
    for (int i=0; i < [blogsArray count]; i++) {
        NSDictionary *userBlog = [blogsArray objectAtIndex:i];
        if ([[userBlog objectForKey:@"value"] intValue] == 1) {
            [mutedBlogsArray addObject:userBlog];
        }
    }
    
    if ([mutedBlogsArray count] > 0) {
        [updatedSettings setValue:mutedBlogsArray forKey:@"muted_blogs"];
    }
    
    if ([updatedSettings count] == 0) {
        return nil;
    }
    
    return updatedSettings;
}

+ (void)saveNotificationSettings {
    NSDictionary *settings = [NotificationsManager notificationSettingsDictionary];
    NSString *token = [[NSUserDefaults standardUserDefaults] objectForKey:NotificationsDeviceToken];
    [[[WPAccount defaultWordPressComAccount] restApi] saveNotificationSettings:settings deviceToken:token success:^{
        DDLogInfo(@"Notification settings successfully sent to WP.com\n Settings: %@", settings);
    } failure:^(NSError *error){
        DDLogError(@"Failed to update notification settings on WP.com %@", error.localizedDescription);
    }];
}

+ (void)fetchNotificationSettingsWithSuccess:(void (^)())success failure:(void (^)(NSError *))failure {
    NSString *token = [[NSUserDefaults standardUserDefaults] objectForKey:NotificationsDeviceToken];
    [[[WPAccount defaultWordPressComAccount] restApi] fetchNotificationSettingsWithDeviceToken:token success:^(NSDictionary *settings) {
        [[NSUserDefaults standardUserDefaults] setObject:settings forKey:NotificationsPreferencesKey];
        DDLogInfo(@"Received notification settings %@", settings);
        if (success) {
            success();
        }
    } failure:^(NSError *error) {
        DDLogError(@"Failed to fetch notification settings %@ with token %@", error.localizedDescription, token);
        if (failure) {
            failure(error);
        }
    }];
}

+ (void)syncPushNotificationInfo {
    NSString *token = [[NSUserDefaults standardUserDefaults] objectForKey:NotificationsDeviceToken];
    WPAccount *account = [WPAccount defaultWordPressComAccount];
    WordPressComApi *api = [account restApi];
    [api syncPushNotificationInfoWithDeviceToken:token success:^(NSDictionary *settings) {
        [[NSUserDefaults standardUserDefaults] setObject:settings forKey:NotificationsPreferencesKey];
        DDLogInfo(@"Synched push notification token and received settings %@", settings);
    } failure:^(NSError *error) {
        DDLogError(@"Failed to receive supported notification list: %@", error);
    }];
}

@end
