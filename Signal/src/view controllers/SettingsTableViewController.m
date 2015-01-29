//
//  SettingsTableViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 03/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "SettingsTableViewController.h"
#import "DJWActionSheet+OWS.h"
#import "SettingsTableViewCell.h"

#import "TSAccountManager.h"
#import "TSStorageManager.h"
#import "Environment.h"
#import "PreferencesUtil.h"
#import "UIUtil.h"
#import <Social/Social.h>

#import "RPServerRequestsManager.h"

#import "TSSocketManager.h"

#import <PastelogKit/Pastelog.h>

#import "Cryptography.h"
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <25519/Curve25519.h>
#import "NSData+hexString.h"
#import "Environment.h"
#import "ContactsManager.h"
#import "Contact.h"
#import "TSStorageManager.h"
#import "TSStorageManager+IdentityKeyStore.h"

#import "PrivacySettingsTableViewController.h"
#import "MediaSettingsTableViewController.h"
#import "AdvancedSettingsTableViewController.h"
#import "AboutTableViewController.h"
#import "PushManager.h"

#define kProfileCellHeight      87.0f
#define kStandardCellHeight     44.0f

#define kNumberOfSections       4

#define kRegisteredNumberRow 0
#define kPrivacyRow          0
#define kAdvancedRow         1
#define kAboutRow            2
#define kNetworkRow          0
#define kUnregisterRow       0

typedef enum {
    kRegisteredRows    = 1,
    kGeneralRows       = 3,
    kNetworkStatusRows = 1,
    kUnregisterRows    = 1,
} kRowsForSection;

typedef enum {
    kRegisteredNumberSection=0,
    kGeneralSection=2,
    kNetworkStatusSection=1,
    kUnregisterSection=3,
} kSection;

@interface SettingsTableViewController () <UIAlertViewDelegate>

@end

@implementation SettingsTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];

    self.tableView.tableFooterView = [[UIView alloc]initWithFrame:CGRectZero];
    self.registeredNumber.text     = [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:[TSAccountManager registeredNumber]];
    [self findAndSetRegisteredName];
    
    [self initializeObserver];
    [TSSocketManager sendNotification];
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SocketOpenedNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SocketClosedNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SocketConnectingNotification object:nil];
}

-(void) findAndSetRegisteredName {
    NSString *name = @"Registered Number:";
    PhoneNumber* myNumber = [PhoneNumber phoneNumberFromE164:[TSAccountManager registeredNumber]];
    Contact *me  = [[Environment.getCurrent contactsManager] latestContactForPhoneNumber:myNumber];
    self.registeredName.text = [me fullName] ? [me fullName] : name;
}
#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return kNumberOfSections;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    
    switch (section) {
        case kRegisteredNumberSection:
            return kRegisteredRows;
        case kGeneralSection:
            return kGeneralRows;
        case kNetworkStatusSection:
            return kNetworkStatusRows;
        case kUnregisterSection:
            return kUnregisterRows;
        default:
            return 0;
    }
}


-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    switch (indexPath.section) {
        case kGeneralSection:
        {
            switch (indexPath.row) {
                case kPrivacyRow:
                {
                    PrivacySettingsTableViewController * vc = [[PrivacySettingsTableViewController alloc]init];
                    NSAssert(self.navigationController != nil, @"Navigation controller must not be nil");
                    NSAssert(vc != nil, @"Privacy Settings View Controller must not be nil");
                    [self.navigationController pushViewController:vc animated:YES];
                    break;
                }
                case kAdvancedRow:
                {
                    AdvancedSettingsTableViewController * vc = [[AdvancedSettingsTableViewController alloc]init];
                    NSAssert(self.navigationController != nil, @"Navigation controller must not be nil");
                    NSAssert(vc != nil, @"Advanced Settings View Controller must not be nil");
                    [self.navigationController pushViewController:vc animated:YES];
                    break;
                }
                case kAboutRow:
                {
                    AboutTableViewController * vc = [[AboutTableViewController alloc]init];
                    NSAssert(self.navigationController != nil, @"Navigation controller must not be nil");
                    NSAssert(vc != nil, @"About View Controller must not be nil");
                    [self.navigationController pushViewController:vc animated:YES];
                    break;
                }
                default:
                    break;
            }
            
            break;
        }
            
        case kNetworkStatusSection:
        {
            break;
        }
            
        case kUnregisterSection:
        {
            [self unregisterUser:self];
            break;
        }
            
        default:
            break;
    }
}


-(IBAction)unregisterUser:(id)sender {
    [TSAccountManager unregisterTextSecureWithSuccess:^{
        [PushManager.sharedManager registrationForPushWithSuccess:^(NSData* pushToken){
            [[RPServerRequestsManager sharedInstance]performRequest:[RPAPICall unregisterWithPushToken:pushToken] success:^(NSURLSessionDataTask *task, id responseObject) {
                [Environment resetAppData];
                exit(0);
            } failure:^(NSURLSessionDataTask *task, NSError *error) {
                SignalAlertView(@"Failed to unregister RedPhone component of Signal", @"");
            }];
        } failure:^{
            SignalAlertView(@"Failed to unregister RedPhone component of Signal", @"");
        }];
    } failure:^(NSError *error) {
       SignalAlertView(@"Failed to unregister TextSecure component of Signal", @"");
    }];
}

-(void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == kNetworkStatusSection) {
        UIAlertView * info = [[UIAlertView alloc]initWithTitle:@"Network Status" message:@"You can check your network status by looking at the colored bar above your inbox." delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
        [info show];
    }
}

#pragma mark - Fingerprint Util

- (NSString*)getFingerprintForTweet:(NSData*)identityKey {
    // idea here is to insert a space every six characters. there is probably a cleverer/more native way to do this.
    
    identityKey = [identityKey prependKeyType];
    NSString *fingerprint = [identityKey hexadecimalString];
    __block NSString*  formattedFingerprint = @"";
    
    [fingerprint enumerateSubstringsInRange:NSMakeRange(0, [fingerprint length])
                                    options:NSStringEnumerationByComposedCharacterSequences
                                 usingBlock:
     ^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
         if (substringRange.location % 5 == 0 && substringRange.location != [fingerprint length]-1&& substringRange.location != 0) {
             substring = [substring stringByAppendingString:@" "];
         }
         formattedFingerprint = [formattedFingerprint stringByAppendingString:substring];
     }];
    return formattedFingerprint;
}

#pragma mark - Socket Status Notifications

-(void)initializeObserver
{
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(socketDidOpen)      name:SocketOpenedNotification object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(socketDidClose)     name:SocketClosedNotification object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(socketIsConnecting) name:SocketConnectingNotification object:nil];
}

-(void)socketDidOpen {
    self.networkStatusLabel.text = @"Connected";
    self.networkStatusLabel.textColor = [UIColor ows_greenColor];
}

-(void)socketDidClose {
    self.networkStatusLabel.text = @"Offline";
    self.networkStatusLabel.textColor = [UIColor ows_redColor];
}

-(void)socketIsConnecting {
    self.networkStatusLabel.text = @"Connecting";
    self.networkStatusLabel.textColor = [UIColor ows_yellowColor];
}

- (IBAction)unwindToUserCancelledChangeNumber:(UIStoryboardSegue *)segue {
    
}

@end
