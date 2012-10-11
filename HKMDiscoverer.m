#import "HKMDiscoverer.h"
#import "HKMJSON.h"
#import "HKMLead.h"
#import "HKMReferralRecord.h"
#import <AddressBook/AddressBook.h>
#import "UIDevice-HKMHardware.h"
#import "HKMOpenUDID.h"

#include <sys/socket.h>
#include <sys/sysctl.h>
#include <net/if.h>
#include <net/if_dl.h>

static HKMDiscoverer *_agent;

@implementation HKMDiscoverer

@synthesize server, SMSDest, appKey, /* runQueryAfterOrder, */ queryStatus, errorMessage, leads, installs, referrals;
@synthesize fbTemplate, emailTemplate, smsTemplate, twitterTemplate;
@synthesize referralMessage;
@synthesize installCode;
@synthesize skipVerificationSms;

- (id) init {
    
    NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
	if (standardUserDefaults) {
		installCode = [[standardUserDefaults objectForKey:@"installCode"] retain];
    }

    contactsDictionary = [[NSMutableDictionary dictionary] retain];
    
    // default
    skipVerificationSms = NO;
    return self;
}

- (void) dealloc 
{
    NSLog(@"HKMDiscover - dealloc invoked");
    [contactsDictionary release];
}

- (BOOL) isRegistered{
    if (installCode == nil || [installCode length] == 0) {
        return NO;
    } else {
        return YES;
    }
}

- (BOOL) verifyDevice:(UIViewController *)vc forceSms:(BOOL) force userName:(NSString *) userName {
    if (verifyDeviceConnection != nil) {
        return NO;
    }
    if (vc != nil) {
        viewController = [vc retain];
        forceVerificationSms = force;
    }
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/newverify", server]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-type"];
    NSMutableData *postBody = [NSMutableData data];
    [postBody appendData:[[NSString stringWithFormat:@"appKey=%@", [appKey stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&addrHash=%@", [self getAddressbookHash:10]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&deviceModel=%@", [[UIDevice currentDevice] platformString]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&deviceOs=%@", [[UIDevice currentDevice] systemVersion]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&openUdid=%@", [[HKMOpenUDID value] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&installToken=%@", [[HKMOpenUDID value] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&macAddress=%@", [[self getMacAddress] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&verifyMessageTemplate=%@", [@"Send text to confirm your device and see which friends has this app.  %installCode%" stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    if (userName != nil) {
        [postBody appendData:[[NSString stringWithFormat:@"&name=%@", [userName stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [postBody appendData:[[NSString stringWithFormat:@"&sdkVersion=%@", [SDKVERSION stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [req setHTTPBody:postBody];
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
    if (connection) {
		verifyDeviceData = [[NSMutableData data] retain];
        verifyDeviceConnection = [connection retain];
	}
    
    return YES;
}

- (BOOL) queryVerifiedStatus {
    if (verificationConnection != nil || installCode == nil) {
        return NO;
    }
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/queryverify", server]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-type"];
    NSMutableData *postBody = [NSMutableData data];
    [postBody appendData:[[NSString stringWithFormat:@"appKey=%@", [appKey stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&installCode=%@", [installCode stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&sdkVersion=%@", [SDKVERSION stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [req setHTTPBody:postBody];
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
    if (connection) {
		verificationData = [[NSMutableData data] retain];
        verificationConnection = [connection retain];
	}
    return YES;
}


- (BOOL) discover:(int) limit {
    if (discoverConnection != nil) {
        return NO;
    }
    
    NSLog(@"installCode is %@", installCode);
    
    NSString *ab = [self getAddressbook:limit];
    if (ab == nil) {
        return NO;
    }
    
    if (![self checkNewAddresses:ab]) {
        if ([contactsDictionary count] == 0)
            [self buildAddressBookDictionary];
        
        NSLog(@"%@", [NSNotificationCenter defaultCenter]);
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_DISCOVER_NO_CHANGE object:nil];
        return YES;
    } 
    
    // build dictionary for quick lookup by phone
    [self buildAddressBookDictionaryAsync];
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/discover", server]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-type"];
    NSMutableData *postBody = [NSMutableData data];
    [postBody appendData:[[NSString stringWithFormat:@"appKey=%@", [appKey stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    if (installCode != nil ) {
        [postBody appendData:[[NSString stringWithFormat:@"&installCode=%@", [installCode stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    
    NSString *encodedJsonStr = (NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)ab, NULL, (CFStringRef)@"!*'();:@&=+$,/?%#[]", kCFStringEncodingUTF8 );
	[postBody appendData:[[NSString stringWithFormat:@"&addressBook=%@", encodedJsonStr] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&deviceModel=%@", [[UIDevice currentDevice] platformString]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&deviceOs=%@", [[UIDevice currentDevice] systemVersion]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&openUdid=%@", [[HKMOpenUDID value] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&installToken=%@", [[HKMOpenUDID value] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&macAddress=%@", [[self getMacAddress] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&sdkVersion=%@", [SDKVERSION stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [req setHTTPBody:postBody];
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
    if (connection) {
		discoverData = [[NSMutableData data] retain];
        discoverConnection = [connection retain];
	}
    // [connection release];

    return YES;
}

- (BOOL) discoverWithoutVzw {
    if (discoverConnection != nil) {
        return NO;
    }
    
    NSLog(@"installCode is %@", installCode);
    
    NSString *ab = [self getAddressbook:0];
    if (ab == nil) {
        return NO;
    }
    
    if (![self checkNewAddresses:ab]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_DISCOVER_NO_CHANGE object:nil];
        return YES;
    }
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/discover", server]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-type"];
    NSMutableData *postBody = [NSMutableData data];
    [postBody appendData:[[NSString stringWithFormat:@"appKey=%@", [appKey stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    if (installCode != nil ) {
        [postBody appendData:[[NSString stringWithFormat:@"&installCode=%@", [installCode stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    NSString *encodedJsonStr = (NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)ab, NULL, (CFStringRef)@"!*'();:@&=+$,/?%#[]", kCFStringEncodingUTF8 );
	[postBody appendData:[[NSString stringWithFormat:@"&addressBook=%@", encodedJsonStr] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&deviceModel=%@", [[UIDevice currentDevice] platformString]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&deviceOs=%@", [[UIDevice currentDevice] systemVersion]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&openUdid=%@", [[HKMOpenUDID value] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&installToken=%@", [[HKMOpenUDID value] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&macAddress=%@", [[self getMacAddress] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&queryDeviceCarrierExclusions=38"] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&sdkVersion=%@", [SDKVERSION stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [req setHTTPBody:postBody];
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
    if (connection) {
		discoverData = [[NSMutableData data] retain];
        discoverConnection = [connection retain];
	}
    // [connection release];
    
    return YES;
}

// contacts must be an array of dictionaries
// Each dictionary has
//    phone
//    firstName
//    lastName
- (BOOL) discoverSelected:(NSMutableArray *)contacts {
    if (discoverConnection != nil) {
        return NO;
    }
    
    NSLog(@"installCode is %@", installCode);
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/selectupdate", server]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-type"];
    NSMutableData *postBody = [NSMutableData data];
    [postBody appendData:[[NSString stringWithFormat:@"appKey=%@", [appKey stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    if (installCode != nil ) {
        [postBody appendData:[[NSString stringWithFormat:@"&installCode=%@", [installCode stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    
    HKMSBJSON *jsonWriter = [[HKMSBJSON new] autorelease];
    jsonWriter.humanReadable = YES;
    NSString *jsonStr = [jsonWriter stringWithObject:contacts];
    NSLog(@"JSON Object --> %@", jsonStr);
    NSString *encodedJsonStr = (NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)jsonStr, NULL, (CFStringRef)@"!*'();:@&=+$,/?%#[]", kCFStringEncodingUTF8 );
    
	[postBody appendData:[[NSString stringWithFormat:@"&addressBook=%@", encodedJsonStr] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&deviceModel=%@", [[UIDevice currentDevice] platformString]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&deviceOs=%@", [[UIDevice currentDevice] systemVersion]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&openUdid=%@", [[HKMOpenUDID value] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&installToken=%@", [[HKMOpenUDID value] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&macAddress=%@", [[self getMacAddress] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&sdkVersion=%@", [SDKVERSION stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [req setHTTPBody:postBody];
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
    if (connection) {
		discoverData = [[NSMutableData data] retain];
        discoverConnection = [connection retain];
	}
    // [connection release];
    
    return YES;
}

- (BOOL) queryLeads {
    if (queryOrderConnection != nil) {
        return NO;
    }
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/queryleads", server]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-type"];
    NSMutableData *postBody = [NSMutableData data];
    [postBody appendData:[[NSString stringWithFormat:@"appKey=%@", [appKey stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&installCode=%@", [installCode stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&sdkVersion=%@", [SDKVERSION stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [req setHTTPBody:postBody];
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
    if (connection) {
		queryOrderData = [[NSMutableData data] retain];
        queryOrderConnection = [connection retain];
	}
    // [connection release];
    
    return YES;
}

- (BOOL) downloadShareTemplates {
    if (shareTemplateConnection != nil) {
        return NO;
    }
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/template", server]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-type"];
    NSMutableData *postBody = [NSMutableData data];
    [postBody appendData:[[NSString stringWithFormat:@"appKey=%@", [appKey stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&installCode=%@", [installCode stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&sdkVersion=%@", [SDKVERSION stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [req setHTTPBody:postBody];
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
    if (connection) {
		shareTemplateData = [[NSMutableData data] retain];
        shareTemplateConnection = [connection retain];
	}
    // [connection release];
    
    return YES;
}

- (BOOL) newReferral:(NSArray *)phones withName:(NSString *)name useVirtualNumber:(BOOL) sendNow {
    
    if (newReferralConnection != nil) {
        return NO;
    }
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/newreferral", server]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-type"];
    NSMutableData *postBody = [NSMutableData data];
    [postBody appendData:[[NSString stringWithFormat:@"appKey=%@", [appKey stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&installCode=%@", [installCode stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    for (NSString *phone in phones) {
        NSString *encodedPhone = (NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)phone, NULL, (CFStringRef)@"!*'();:@&=+$,/?%#[]", kCFStringEncodingUTF8 );
        [postBody appendData:[[NSString stringWithFormat:@"&phone=%@", encodedPhone] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    if (name != nil) {
        [postBody appendData:[[NSString stringWithFormat:@"&name=%@", [name stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [postBody appendData:[@"&useShortUrl=true" dataUsingEncoding:NSUTF8StringEncoding]];
    if (sendNow) {
        [postBody appendData:[@"&sendNow=true" dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [postBody appendData:[[NSString stringWithFormat:@"&sdkVersion=%@", [SDKVERSION stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [req setHTTPBody:postBody];
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
    if (connection) {
		newReferralData = [[NSMutableData data] retain];
        newReferralConnection = [connection retain];
	}
    // [connection release];
    
    return YES;
}

- (BOOL) updateReferral:(BOOL) sent {
    if (updateReferralConnection != nil) {
        return NO;
    }
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/updatereferral", server]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-type"];
    NSMutableData *postBody = [NSMutableData data];
    [postBody appendData:[[NSString stringWithFormat:@"appKey=%@", [appKey stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&installCode=%@", [installCode stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&referralId=%d", referralId] dataUsingEncoding:NSUTF8StringEncoding]];
    if (sent) {
        [postBody appendData:[@"&action=sent" dataUsingEncoding:NSUTF8StringEncoding]];
    } else {
        [postBody appendData:[@"&action=cancel" dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [postBody appendData:[[NSString stringWithFormat:@"&sdkVersion=%@", [SDKVERSION stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [req setHTTPBody:postBody];
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
    if (connection) {
		updateReferralData = [[NSMutableData data] retain];
        updateReferralConnection = [connection retain];
	}
    // [connection release];
    
    return YES;
}

- (BOOL) queryInstalls:(NSString *)direction {
    if (queryInstallsConnection != nil) {
        return NO;
    }
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/queryinstalls", server]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-type"];
    NSMutableData *postBody = [NSMutableData data];
    [postBody appendData:[[NSString stringWithFormat:@"appKey=%@", [appKey stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&installCode=%@", [installCode stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&reference=%@", [direction stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&sdkVersion=%@", [SDKVERSION stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [req setHTTPBody:postBody];
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
    if (connection) {
		queryInstallsData = [[NSMutableData data] retain];
        queryInstallsConnection = [connection retain];
	}
    // [connection release];
    
    return YES;
}

- (BOOL) queryReferral {
    if (queryReferralConnection != nil) {
        return NO;
    }
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/queryreferral", server]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-type"];
    NSMutableData *postBody = [NSMutableData data];
    [postBody appendData:[[NSString stringWithFormat:@"appKey=%@", [appKey stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&installCode=%@", [installCode stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&sdkVersion=%@", [SDKVERSION stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [req setHTTPBody:postBody];
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
    if (connection) {
		queryReferralData = [[NSMutableData data] retain];
        queryReferralConnection = [connection retain];
	}
    // [connection release];
    
    return YES;
}

- (BOOL) newInstall {
    if (newInstallConnection != nil) {
        return NO;
    }
    if (installCode != nil && ![@"" isEqualToString:installCode]) {
        return NO;
    }
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/newinstall", server]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-type"];
    NSMutableData *postBody = [NSMutableData data];
    [postBody appendData:[[NSString stringWithFormat:@"appKey=%@", [appKey stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&addrHash=%@", [self getAddressbookHash:10]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&openUdid=%@", [[HKMOpenUDID value] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&installToken=%@", [[HKMOpenUDID value] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&macAddress=%@", [[self getMacAddress] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&deviceModel=%@", [[UIDevice currentDevice] platformString]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&deviceOs=%@", [[UIDevice currentDevice] systemVersion]] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"&sdkVersion=%@", [SDKVERSION stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]];
    [req setHTTPBody:postBody];
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:req delegate:self];
    if (connection) {
		newInstallData = [[NSMutableData data] retain];
        newInstallConnection = [connection retain];
	}
    // [connection release];
    
    return YES;
}

- (NSString *) getAddressbook:(int) limit {
    ABAddressBookRef ab = ABAddressBookCreate();
    
    CFArrayRef allPeople = ABAddressBookCopyArrayOfAllPeople(ab);
    CFIndex nPeople = ABAddressBookGetPersonCount(ab);
    if (nPeople > MAX_ADDRESSBOOK_UPLOAD_SIZE)
        nPeople = MAX_ADDRESSBOOK_UPLOAD_SIZE;
    if (limit > 0 && nPeople > limit) {
        nPeople = limit;
    }
    
    NSMutableArray *phones = [[NSMutableArray alloc] init];
    for (int i = 0; i < nPeople; i++) {
        ABRecordRef ref = CFArrayGetValueAtIndex(allPeople, i);
        CFStringRef firstName = ABRecordCopyValue(ref, kABPersonFirstNameProperty);
        CFStringRef lastName = ABRecordCopyValue(ref, kABPersonLastNameProperty);
        
        NSString *firstNameStr = (NSString *) firstName;
        if (firstNameStr == nil) {
            firstNameStr = @"";
        }
        if (![firstNameStr canBeConvertedToEncoding:NSASCIIStringEncoding]) {
            firstNameStr = @"NONASCII";
        }
        NSString *lastNameStr = (NSString *) lastName;
        if (lastNameStr == nil) {
            lastNameStr = @"";
        }
        if (![lastNameStr canBeConvertedToEncoding:NSASCIIStringEncoding]) {
            lastNameStr = @"NONASCII";
        }
        
        ABMultiValueRef ps = ABRecordCopyValue(ref, kABPersonPhoneProperty);
        CFIndex count = ABMultiValueGetCount (ps);
        for (int i = 0; i < count; i++) {
            CFStringRef phone = ABMultiValueCopyValueAtIndex (ps, i);
            
            NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithCapacity:16];
            [dic setObject:((NSString *) phone) forKey:@"phone"];
            [dic setObject:((NSString *) firstNameStr) forKey:@"firstName"];
            [dic setObject:((NSString *) lastNameStr) forKey:@"lastName"];
            [phones addObject:dic];
            [dic release];
            
            if (phone) {
                CFRelease(phone);
            }
        }
        
        if (firstName) {
            CFRelease(firstName);
        }
        if (lastName) {
            CFRelease(lastName);
        }
    }
	if (allPeople) {
        CFRelease(allPeople);
    }
    
    // create json for phone and name based on phones
    HKMSBJSON *jsonWriter = [[HKMSBJSON new] autorelease];
    jsonWriter.humanReadable = YES;
    NSString *jsonStr = [jsonWriter stringWithObject:phones];
    NSLog(@"JSON Object --> %@", jsonStr);
    
    return jsonStr;
}

- (NSString *) getAddressbookHash:(int) limit {
    ABAddressBookRef ab = ABAddressBookCreate();
    
    CFArrayRef allPeople = ABAddressBookCopyArrayOfAllPeople(ab);
    CFIndex nPeople = ABAddressBookGetPersonCount(ab);
    if (limit > 0 && nPeople > limit) {
        nPeople = limit;
    }
    
    NSMutableString *hashes = [NSMutableString stringWithCapacity:1024];
    for (int i = 0; i < nPeople; i++) {
        ABRecordRef ref = CFArrayGetValueAtIndex(allPeople, i);
        
        ABMultiValueRef ps = ABRecordCopyValue(ref, kABPersonPhoneProperty);
        CFIndex count = ABMultiValueGetCount (ps);
        for (int i = 0; i < count; i++) {
            CFStringRef phone = ABMultiValueCopyValueAtIndex (ps, i);
            NSString *fphone = [self formatPhone:((NSString *) phone)];
            int hash = [self murmurHash:fphone];
            [hashes appendFormat:@"%d|", hash];
            NSLog(@"Murmur Hash of addresses %@ is %d", fphone, hash);
            if (phone) {
                CFRelease(phone);
            }
        }
    }
	if (allPeople) {
        CFRelease(allPeople);
    }
    
    NSString *res = @"";
    if ([hashes length] > 0) {
        res = [hashes substringToIndex:([hashes length]-1)];
    }
    NSLog(@"Murmur Hash outcome is %@", res);
    return res;
}

- (void) createVerificationSms {
    fullScreen = [UIApplication sharedApplication].statusBarHidden;
    NSString *platform = [[UIDevice currentDevice] platformString];
    NSString *model = [[UIDevice currentDevice] model];
    if (viewController != nil) {
        if ([MFMessageComposeViewController canSendText] && [platform hasPrefix:@"iPhone"] && ![model isEqualToString:@"iPhone Simulator"] && !skipVerificationSms) {
            NSLog(@"Show SMS confirmation");
            [UIApplication sharedApplication].statusBarHidden = NO;
            MFMessageComposeViewController *controller = [[[MFMessageComposeViewController alloc] init] autorelease];
            controller.body = verifyMessage;
            controller.recipients = [NSArray arrayWithObjects:SMSDest, nil];
            controller.messageComposeDelegate = self;
            [viewController presentModalViewController:controller animated:YES];
        } else {
            NSLog(@"Not a SMS device. Fail silently.");
            [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_NOT_SMS_DEVICE object:nil];
        }
    }
}

- (NSString *) lookupNameFromPhone:(NSString *)p {
    double start = [[NSDate date] timeIntervalSince1970];

    NSString *name;
    
    ABAddressBookRef ab = ABAddressBookCreate();
    
    CFArrayRef allPeople = ABAddressBookCopyArrayOfAllPeople(ab);
    CFIndex nPeople = ABAddressBookGetPersonCount(ab);
    
    for (int i = 0; i < nPeople; i++) {
        ABRecordRef ref = CFArrayGetValueAtIndex(allPeople, i);
        CFStringRef firstName = ABRecordCopyValue(ref, kABPersonFirstNameProperty);
        CFStringRef lastName = ABRecordCopyValue(ref, kABPersonLastNameProperty);
        CFStringRef suffix = ABRecordCopyValue(ref, kABPersonSuffixProperty);
        
        NSString *firstNameStr = (NSString *) firstName;
        if (firstNameStr == nil) {
            firstNameStr = @"";
        }
        NSString *lastNameStr = (NSString *) lastName;
        if (lastNameStr == nil) {
            lastNameStr = @"";
        }
        NSString *suffixStr = (NSString *) suffix;
        if (suffixStr == nil) {
            suffixStr = @"";
        }
        
        ABMultiValueRef ps = ABRecordCopyValue(ref, kABPersonPhoneProperty);
        CFIndex count = ABMultiValueGetCount (ps);
        for (int i = 0; i < count; i++) {
            CFStringRef phone = ABMultiValueCopyValueAtIndex (ps, i);
            
            if ([p isEqualToString:[self formatPhone:((NSString *) phone)]]) {
                name = [NSString stringWithFormat:@"%@ %@ %@", firstNameStr, lastNameStr, suffixStr];
                break;
            }
            
            if (phone) {
                CFRelease(phone);
            }
        }
        
        if (firstName) {
            CFRelease(firstName);
        }
        if (lastName) {
            CFRelease(lastName);
        }
    }
	if (allPeople) {
        CFRelease(allPeople);
    }
    double end = [[NSDate date] timeIntervalSince1970];
    double difference = end - start;    

    NSLog(@"lookupNameFromPhone - Time elapsed %f", difference);
    return name;
}

- (void) buildAddressBookDictionaryAsync {
    /* Operation Queue init (autorelease) */
    NSOperationQueue *queue = [NSOperationQueue new];
    
    /* Create our NSInvocationOperation to call buildAddressBookDictionary, passing in nil */
    NSInvocationOperation *operation = [[NSInvocationOperation alloc] initWithTarget:self
                                                                            selector:@selector(buildAddressBookDictionary)
                                                                              object:nil];
    
    /* Add the operation to the queue */
    [queue addOperation:operation];
    [operation release];
}

- (void) buildAddressBookDictionary {
    double start = [[NSDate date] timeIntervalSince1970];
    
    [contactsDictionary removeAllObjects];
    ABAddressBookRef ab = ABAddressBookCreate();
    
    CFArrayRef allPeople = ABAddressBookCopyArrayOfAllPeople(ab);
    CFIndex nPeople = ABAddressBookGetPersonCount(ab);
    
    for (int i = 0; i < nPeople; i++) {
        ABRecordRef ref = CFArrayGetValueAtIndex(allPeople, i);
        
        ABRecordID recordId = ABRecordGetRecordID(ref); // get record id from address book record
        
        ABMultiValueRef ps = ABRecordCopyValue(ref, kABPersonPhoneProperty);
        CFIndex count = ABMultiValueGetCount (ps);
        for (int i = 0; i < count; i++) {
            CFStringRef phone = ABMultiValueCopyValueAtIndex (ps, i);
            [contactsDictionary setObject:[NSNumber numberWithInteger:recordId] forKey:[self formatPhone:((NSString *) phone)]];
            
            if (phone) {
                CFRelease(phone);
            }
        }
    }
	if (allPeople) {
        CFRelease(allPeople);
    }
    double end = [[NSDate date] timeIntervalSince1970];
    double difference = end - start;    
    
    NSLog(@"buildAddressBookDictionary - Time elapsed %f", difference);
}

//- (void) buildAddressBookDictionary {
//    double start = [[NSDate date] timeIntervalSince1970];
//
//    [contactsDictionary removeAllObjects];
//    ABAddressBookRef ab = ABAddressBookCreate();
//    
//    CFArrayRef allPeople = ABAddressBookCopyArrayOfAllPeople(ab);
//    CFIndex nPeople = ABAddressBookGetPersonCount(ab);
//    
//    for (int i = 0; i < nPeople; i++) {
//        ABRecordRef ref = CFArrayGetValueAtIndex(allPeople, i);
//        CFStringRef firstName = ABRecordCopyValue(ref, kABPersonFirstNameProperty);
//        CFStringRef lastName = ABRecordCopyValue(ref, kABPersonLastNameProperty);
//        CFStringRef suffix = ABRecordCopyValue(ref, kABPersonSuffixProperty);
//        
//        NSString *firstNameStr = (NSString *) firstName;
//        if (firstNameStr == nil) {
//            firstNameStr = @"";
//        }
//        NSString *lastNameStr = (NSString *) lastName;
//        if (lastNameStr == nil) {
//            lastNameStr = @"";
//        }
//        NSString *suffixStr = (NSString *) suffix;
//        if (suffixStr == nil) {
//            suffixStr = @"";
//        }
//        
//        ABMultiValueRef ps = ABRecordCopyValue(ref, kABPersonPhoneProperty);
//        CFIndex count = ABMultiValueGetCount (ps);
//        for (int i = 0; i < count; i++) {
//            CFStringRef phone = ABMultiValueCopyValueAtIndex (ps, i);
//            [contactsDictionary setObject:[NSString stringWithFormat:@"%@ %@ %@", firstNameStr, lastNameStr, suffixStr] forKey:[self formatPhone:((NSString *) phone)]];
//            
//            if (phone) {
//                CFRelease(phone);
//            }
//        }
//        
//        if (firstName) {
//            CFRelease(firstName);
//        }
//        if (lastName) {
//            CFRelease(lastName);
//        }
//    }
//	if (allPeople) {
//        CFRelease(allPeople);
//    }
//    double end = [[NSDate date] timeIntervalSince1970];
//    double difference = end - start;    
//    
//    NSLog(@"buildAddressBookDictionary - Time elapsed %f", difference);
//}

// Update lead with info from address book
- (void) updateContactDetails:(HKMLead *)intoLead {
    NSNumber *contactId = [contactsDictionary objectForKey:intoLead.phone]; 
    if (!contactId) {
        NSLog(@"updateContactDetails - contact[%@] not found in dictionary", intoLead.phone);
        return;
    }
    
    // Get contact from Address Book
    ABAddressBookRef addressBook = ABAddressBookCreate();
    ABRecordID recordId = (ABRecordID)[contactId intValue];
    ABRecordRef person = ABAddressBookGetPersonWithRecordID(addressBook, recordId);
    
    CFStringRef firstName = ABRecordCopyValue(person, kABPersonFirstNameProperty);
    CFStringRef lastName = ABRecordCopyValue(person, kABPersonLastNameProperty);
    CFStringRef suffix = ABRecordCopyValue(person, kABPersonSuffixProperty);
    
    NSString *firstNameStr = (NSString *) firstName;
    if (firstNameStr == nil) {
        firstNameStr = @"";
    }
    NSString *lastNameStr = (NSString *) lastName;
    if (lastNameStr == nil) {
        lastNameStr = @"";
    }
    NSString *suffixStr = (NSString *) suffix;
    if (suffixStr == nil) {
        suffixStr = @"";
    }

    if (firstName) {
        CFRelease(firstName);
    }
    if (lastName) {
        CFRelease(lastName);
    }
    if (suffix) {
        CFRelease(suffix);
    }
    
    NSString *fullName = [NSString stringWithFormat:@"%@ %@ %@", firstNameStr, lastNameStr, suffixStr];
    intoLead.name = fullName;
    
    // Check for contact picture
    if (person != nil && ABPersonHasImageData(person)) {
        if ( &ABPersonCopyImageDataWithFormat != nil ) {
            // iOS >= 4.1
            intoLead.image = [UIImage imageWithData:(NSData *)ABPersonCopyImageDataWithFormat(person, kABPersonImageFormatThumbnail)];
        } else 
            // iOS < 4.1
            intoLead.image = [UIImage imageWithData:(NSData *)ABPersonCopyImageData(person)];
    }
}
    
- (NSString *) formatPhone:(NSString *)p {
    p = [p stringByReplacingOccurrencesOfString:@"(" withString:@""];
    p = [p stringByReplacingOccurrencesOfString:@")" withString:@""];
    p = [p stringByReplacingOccurrencesOfString:@" " withString:@""];
    p = [p stringByReplacingOccurrencesOfString:@"-" withString:@""];
    p = [p stringByReplacingOccurrencesOfString:@"+" withString:@""];
    
    int length = [p length];
    if(length == 10) {
        p = [NSString stringWithFormat:@"+1%@", p];
    } else if (length == 11) {
        p = [NSString stringWithFormat:@"+%@", p];
    }
    
    return p;
}

- (BOOL) checkNewAddresses:(NSString *)ab {
    NSString *saved = [self cachedAddresses];
    if (saved == nil || ![saved isEqualToString:ab]) {
        addressbook = [ab retain];
        return YES;
    } else {
        return NO;
    }
    return YES;
}

- (NSString *) cachedAddresses {
    NSString *saved = nil;
    NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
    if (standardUserDefaults) {
        saved = [standardUserDefaults objectForKey:@"HOOKADDRESSBOOK"];
    }
    return saved;
}

- (NSString *) getMacAddress {
    int                 mgmtInfoBase[6];
    char                *msgBuffer = NULL;
    NSString            *errorFlag = NULL;
    size_t              length;
    
    // Setup the management Information Base (mib)
    mgmtInfoBase[0] = CTL_NET;        // Request network subsystem
    mgmtInfoBase[1] = AF_ROUTE;       // Routing table info
    mgmtInfoBase[2] = 0;
    mgmtInfoBase[3] = AF_LINK;        // Request link layer information
    mgmtInfoBase[4] = NET_RT_IFLIST;  // Request all configured interfaces
    
    // With all configured interfaces requested, get handle index
    if ((mgmtInfoBase[5] = if_nametoindex("en0")) == 0)
        errorFlag = @"if_nametoindex failure";
    // Get the size of the data available (store in len)
    else if (sysctl(mgmtInfoBase, 6, NULL, &length, NULL, 0) < 0)
        errorFlag = @"sysctl mgmtInfoBase failure";
    // Alloc memory based on above call
    else if ((msgBuffer = (char *) malloc(length)) == NULL)
        errorFlag = @"buffer allocation failure";
    // Get system information, store in buffer
    else if (sysctl(mgmtInfoBase, 6, msgBuffer, &length, NULL, 0) < 0)
    {
        free(msgBuffer);
        errorFlag = @"sysctl msgBuffer failure";
    }
    else
    {
        // Map msgbuffer to interface message structure
        struct if_msghdr *interfaceMsgStruct = (struct if_msghdr *) msgBuffer;
        
        // Map to link-level socket structure
        struct sockaddr_dl *socketStruct = (struct sockaddr_dl *) (interfaceMsgStruct + 1);
        
        // Copy link layer address data in socket structure to an array
        unsigned char macAddress[6];
        memcpy(&macAddress, socketStruct->sdl_data + socketStruct->sdl_nlen, 6);
        
        // Read from char array into a string object, into traditional Mac address format
        NSString *macAddressString = [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X",
                                      macAddress[0], macAddress[1], macAddress[2], macAddress[3], macAddress[4], macAddress[5]];
        NSLog(@"Mac Address: %@", macAddressString);
        
        // Release the buffer memory
        free(msgBuffer);
        
        return macAddressString;
    }
    
    // Error...
    NSLog(@"Error: %@", errorFlag);
    
    return errorFlag;
}

- (int) murmurHash:(NSString *)s {
    NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
    return MurmurHash2([d bytes], [d length], 0);
}

unsigned int MurmurHash2 ( const void * key, int len, unsigned int seed ) {
    // 'm' and 'r' are mixing constants generated offline.
    // They're not really 'magic', they just happen to work well.
    
    const unsigned int m = 0x5bd1e995;
    const int r = 24;
    
    // Initialize the hash to a 'random' value
    
    unsigned int h = seed ^ len;
    
    // Mix 4 bytes at a time into the hash
    
    const unsigned char * data = (const unsigned char *)key;
    
    while(len >= 4)
    {
        unsigned int k = *(unsigned int *)data;
        
        k *= m;
        k ^= k >> r;
        k *= m;
        
        h *= m;
        h ^= k;
        
        data += 4;
        len -= 4;
    }
    
    // Handle the last few bytes of the input array
    
    switch(len)
    {
        case 3: h ^= data[2] << 16;
        case 2: h ^= data[1] << 8;
        case 1: h ^= data[0];
            h *= m;
    };
    
    // Do a few final mixes of the hash to ensure the last few
    // bytes are well-incorporated.
    
    h ^= h >> 13;
    h *= m;
    h ^= h >> 15;
    
    return h;
}


- (void)messageComposeViewController:(MFMessageComposeViewController *)controller didFinishWithResult:(MessageComposeResult)result {
    
    [viewController dismissModalViewControllerAnimated:YES];
    [UIApplication sharedApplication].statusBarHidden = fullScreen;
    if (fullScreen) {
        CGRect nFrame = viewController.view.frame;
        nFrame.size.height = nFrame.size.height + 20;
        nFrame.origin.y = nFrame.origin.y - 20;
        viewController.view.frame = nFrame;
    }
    
    if (result == MessageComposeResultCancelled) {
        if (forceVerificationSms) {
            // the SMS stays. No cancel
            UIAlertView* alert = [[UIAlertView alloc] init];
            alert.title = @"Confirmation";
            alert.message = @"You can only proceed after you send the confirmation SMS";
            [alert addButtonWithTitle:@"Okay"];
            // alert.cancelButtonIndex = 0;
            alert.delegate = self;
            [alert show];
            [alert release];
        } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_VERIFICATION_SMS_NOT_SENT object:nil];
        }
        
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_VERIFICATION_SMS_SENT object:nil];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex == 0) {
		[self createVerificationSms];
	}
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
	NSLog (@"Received response");
    if (connection == verifyDeviceConnection) {
        [verifyDeviceData setLength:0];
    }
    if (connection == verificationConnection) {
        [verificationData setLength:0];
    }
    if (connection == discoverConnection) {
        [discoverData setLength:0];
    }
    if (connection == queryOrderConnection) {
        [queryOrderData setLength:0];
    }
    if (connection == shareTemplateConnection) {
        [shareTemplateData setLength:0];
    }
    if (connection == newReferralConnection) {
        [newReferralData setLength:0];
    }
    if (connection == updateReferralConnection) {
        [updateReferralData setLength:0];
    }
    if (connection == queryInstallsConnection) {
        [queryInstallsData setLength:0];
    }
    if (connection == queryReferralConnection) {
        [queryReferralData setLength:0];
    }
    if (connection == newInstallConnection) {
        [newInstallData setLength:0];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    if (connection == verifyDeviceConnection) {
        [verifyDeviceData appendData:data];
    }
    if (connection == verificationConnection) {
        [verificationData appendData:data];
    }
    if (connection == discoverConnection) {
        [discoverData appendData:data];
    }
    if (connection == queryOrderConnection) {
        [queryOrderData appendData:data];
    }
    if (connection == shareTemplateConnection) {
        [shareTemplateData appendData:data];
    }
    if (connection == newReferralConnection) {
        [newReferralData appendData:data];
    }
    if (connection == updateReferralConnection) {
        [updateReferralData appendData:data];
    }
    if (connection == queryInstallsConnection) {
        [queryInstallsData appendData:data];
    }
    if (connection == queryReferralConnection) {
        [queryReferralData appendData:data];
    }
    if (connection == newInstallConnection) {
        [newInstallData appendData:data];
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    NSLog (@"Received error with code %d", error.code);
    if (connection == verifyDeviceConnection) {
        [verifyDeviceData release];
        [verifyDeviceConnection release];
        verifyDeviceConnection = nil;
    }
    if (connection == verificationConnection) {
        [verificationData release];
        [verificationConnection release];
        verificationConnection = nil;
    }
    if (connection == discoverConnection) {
        [discoverData release];
        [discoverConnection release];
        discoverConnection = nil;
    }
    if (connection == queryOrderConnection) {
        [queryOrderData release];
        [queryOrderConnection release];
        queryOrderConnection = nil;
    }
    if (connection == shareTemplateConnection) {
        [shareTemplateData release];
        [shareTemplateConnection release];
        shareTemplateConnection = nil;
    }
    if (connection == newReferralConnection) {
        [newReferralData release];
        [newReferralConnection release];
        newReferralConnection = nil;
    }
    if (connection == updateReferralConnection) {
        [updateReferralData release];
        [updateReferralConnection release];
        updateReferralConnection = nil;
    }
    if (connection == queryInstallsConnection) {
        [queryInstallsData release];
        [queryInstallsConnection release];
        queryInstallsConnection = nil;
    }
    if (connection == queryReferralConnection) {
        [queryReferralData release];
        [queryReferralConnection release];
        queryReferralConnection = nil;
    }
    if (connection == newInstallConnection) {
        [newInstallData release];
        [newInstallConnection release];
        newInstallConnection = nil;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_NETWORK_ERROR object:nil];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
	NSLog (@"Finished loading data");
    
    if (connection == verifyDeviceConnection) {
        NSString *dataStr = [[[NSString alloc] initWithData:verifyDeviceData encoding:NSUTF8StringEncoding] autorelease];
        NSLog (@"verifyDevice data is %@", dataStr);
        [verifyDeviceData release];
        
        HKMSBJSON *jsonReader = [[HKMSBJSON new] autorelease];
        NSDictionary *resp = [jsonReader objectWithString:dataStr];
        if ([[resp objectForKey:@"status"] intValue] == 1000) {
            NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
            if (standardUserDefaults) {
                installCode = [[resp objectForKey:@"installCode"] retain];
                [standardUserDefaults setObject:installCode forKey:@"installCode"];
                [standardUserDefaults synchronize];
            }
            verifyMessage = [[resp objectForKey:@"verifyMessage"] retain];
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_VERIFY_DEVICE_COMPLETE object:[resp objectForKey:@"status"]];
        
        [self createVerificationSms];
        
        [verifyDeviceConnection release];
        verifyDeviceConnection = nil;
    }
    
    if (connection == verificationConnection) {
        NSString *dataStr = [[[NSString alloc] initWithData:verificationData encoding:NSUTF8StringEncoding] autorelease];
        NSLog (@"verification data is %@", dataStr);
        [verificationData release];
        
        HKMSBJSON *jsonReader = [[HKMSBJSON new] autorelease];
        NSDictionary *resp = [jsonReader objectWithString:dataStr];
        if ([[resp objectForKey:@"status"] intValue] == 1000) {
            NSString *verified = [resp objectForKey:@"verified"];
            if ([verified isEqualToString:@"true"]) {
                [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_DEVICE_VERIFIED object:nil];
            } else {
                [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_DEVICE_NOT_VERIFIED object:nil];
            }
        }
        
        [verificationConnection release];
        verificationConnection = nil;
    }
    
    if (connection == discoverConnection) {
        NSString *dataStr = [[[NSString alloc] initWithData:discoverData encoding:NSUTF8StringEncoding] autorelease];
        NSLog (@"discover data is %@", dataStr);
        [discoverData release];
        
        HKMSBJSON *jsonReader = [[HKMSBJSON new] autorelease];
        NSDictionary *resp = [jsonReader objectWithString:dataStr];
        if ([[resp objectForKey:@"status"] intValue] == 1000) {
            NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
            if (standardUserDefaults) {
                installCode = [[resp objectForKey:@"installCode"] retain];
                [standardUserDefaults setObject:installCode forKey:@"installCode"];
                
                // save the addressbook cache upon success
                [standardUserDefaults setObject:addressbook forKey:@"HOOKADDRESSBOOK"];
                [standardUserDefaults synchronize];
            }
            
            NSLog(@"installCode is %@", installCode);
            
            [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_DISCOVER_COMPLETE object:nil];
        } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_DISCOVER_FAILED object:nil];
        }
        
        [discoverConnection release];
        discoverConnection = nil;
    }
        
    if (connection == queryOrderConnection) {
        NSString *dataStr = [[[NSString alloc] initWithData:queryOrderData encoding:NSUTF8StringEncoding] autorelease];
        NSLog (@"query order data is %@", dataStr);
        [queryOrderData release];
        
        HKMSBJSON *jsonReader = [[HKMSBJSON new] autorelease];
        NSDictionary *resp = [jsonReader objectWithString:dataStr];
        int status = [[resp objectForKey:@"status"] intValue];
        if (status == 1000) {
            queryStatus = YES;
        } else {
            queryStatus = NO;
            if (status == 3502) {
                [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_ADDRESSBOOK_CACHE_EXPIRED object:nil];
                return;
            }
        }
        if (status == 1000 || status == 1500) {
            leads = [[NSMutableArray arrayWithCapacity:16] retain];
            NSArray *ls = [resp objectForKey:@"leads"];
            if (ls != nil && [ls count] > 0) {
                for (NSDictionary *d in ls) {
                    HKMLead *lead = [[HKMLead alloc] init];
                    lead.phone = [d objectForKey:@"phone"];
                    lead.osType = [d objectForKey:@"osType"];
                    lead.invitationCount = [[resp objectForKey:@"invitationCount"] intValue];
//                    lead.name = [[HKMDiscoverer agent] lookupNameFromPhone:lead.phone];
//                    lead.name = [[HKMDiscoverer agent] lookupNameFromContactDictionary:lead.phone];
                    [[HKMDiscoverer agent] updateContactDetails:lead];
                    NSString *dateStr = [d objectForKey:@"lastInvitationSent"];
                    if (dateStr == nil || [@"" isEqualToString:dateStr]) {
                    } else {
                        NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
                        [dateFormat setDateFormat:@"yyyy-MM-dd HH:mm:ss.S"];
                        lead.lastInvitationSent = [dateFormat dateFromString:dateStr];
                        [dateFormat release];
                    }
                    
                    [leads addObject:lead];
                }
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_QUERY_ORDER_COMPLETE object:nil];
        } else {
            errorMessage = [[resp objectForKey:@"desc"] retain];
            [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_QUERY_ORDER_FAILED object:nil];
        }
        /*
        else if ([[resp objectForKey:@"status"] intValue] == 1234) {
            // pending. Let's run this again after some delay
            // [self performSelector:@selector(queryOrder) withObject:nil afterDelay:10.0];
            [NSTimer scheduledTimerWithTimeInterval:60.0 target:self selector:@selector(queryOrder) userInfo:nil repeats:NO];
        }
        */
        
        [queryOrderConnection release];
        queryOrderConnection = nil;
    }
    
    if (connection == shareTemplateConnection) {
        NSString *dataStr = [[NSString alloc] initWithData:shareTemplateData encoding:NSUTF8StringEncoding];
        NSLog (@"share template data is %@", dataStr);
        [shareTemplateData release];
        
        HKMSBJSON *jsonReader = [[HKMSBJSON new] autorelease];
        NSDictionary *resp = [jsonReader objectWithString:dataStr];
        if ([@"ok" isEqualToString:[resp objectForKey:@"status"]]) {
            fbTemplate = [[resp objectForKey:@"fb"] retain];
            twitterTemplate = [[resp objectForKey:@"twitter"] retain];
            emailTemplate = [[resp objectForKey:@"email"] retain];
            smsTemplate = [[resp objectForKey:@"sms"] retain];
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_DOWNLOAD_SHARE_TEMPLATE_COMPLETE object:nil];
        
        [shareTemplateConnection release];
        shareTemplateConnection = nil;
    }
    
    if (connection == newReferralConnection) {
        NSString *dataStr = [[NSString alloc] initWithData:newReferralData encoding:NSUTF8StringEncoding];
        NSLog (@"new referral data is %@", dataStr);
        [newReferralData release];
        
        HKMSBJSON *jsonReader = [[HKMSBJSON new] autorelease];
        NSDictionary *resp = [jsonReader objectWithString:dataStr];
        if ([[resp objectForKey:@"status"] intValue] == 1000) {
            referralId = [[resp objectForKey:@"referralId"] intValue];
            referralMessage = [[resp objectForKey:@"referralMessage"] retain];
            invitationUrl = [[resp objectForKey:@"url"] retain];
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_NEW_REFERRAL_COMPLETE object:nil];
        
        [newReferralConnection release];
        newReferralConnection = nil;
    }
    
    if (connection == updateReferralConnection) {
        NSString *dataStr = [[NSString alloc] initWithData:updateReferralData encoding:NSUTF8StringEncoding];
        NSLog (@"update referral data is %@", dataStr);
        [updateReferralData release];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_UPDATE_REFERRAL_COMPLETE object:nil];
        
        [updateReferralConnection release];
        updateReferralConnection = nil;
    }
    
    if (connection == queryInstallsConnection) {
        NSString *dataStr = [[NSString alloc] initWithData:queryInstallsData encoding:NSUTF8StringEncoding];
        NSLog (@"query installs data is %@", dataStr);
        [queryInstallsData release];
        
        HKMSBJSON *jsonReader = [[HKMSBJSON new] autorelease];
        NSDictionary *resp = [jsonReader objectWithString:dataStr];
        int status = [[resp objectForKey:@"status"] intValue];
        if (status == 1000) {
            installs = [[NSMutableArray arrayWithCapacity:16] retain];
            NSArray *ls = [resp objectForKey:@"leads"];
            if (ls != nil && [ls count] > 0) {
                for (NSString *p in ls) {
                    HKMLead *lead = [[HKMLead alloc] init];
                    lead.phone = p;
                    lead.name = [[HKMDiscoverer agent] lookupNameFromPhone:lead.phone];
                    [installs addObject:lead];
                }
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_QUERY_INSTALLS_COMPLETE object:nil];
        } else {
            if (status == 3502) {
                [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_ADDRESSBOOK_CACHE_EXPIRED object:nil];
                return;
            }
            errorMessage = [[resp objectForKey:@"desc"] retain];
            [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_QUERY_INSTALLS_FAILED object:nil];
        }
        
        [queryInstallsConnection release];
        queryInstallsConnection = nil;
    }
    
    if (connection == queryReferralConnection) {
        NSString *dataStr = [[NSString alloc] initWithData:queryReferralData encoding:NSUTF8StringEncoding];
        NSLog (@"query referral data is %@", dataStr);
        [queryReferralData release];
        
        HKMSBJSON *jsonReader = [[HKMSBJSON new] autorelease];
        NSDictionary *resp = [jsonReader objectWithString:dataStr];
        int status = [[resp objectForKey:@"status"] intValue];
        if (status == 1000) {
            referrals = [[NSMutableArray arrayWithCapacity:16] retain];
            NSArray *ls = [resp objectForKey:@"referrals"];
            if (ls != nil && [ls count] > 0) {
                for (NSDictionary *d in ls) {
                    HKMReferralRecord *rec = [[HKMReferralRecord alloc] init];
                    rec.totalClickThrough = [[d objectForKey:@"totalClickThrough"] intValue];
                    rec.totalInvitee = [[d objectForKey:@"totalInvitee"] intValue];
                    NSString *dateStr = [d objectForKey:@"date"];
                    if (dateStr == nil || [@"" isEqualToString:dateStr]) {
                    } else {
                        NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
                        [dateFormat setDateFormat:@"yyyy-MM-dd HH:mm:ss.S"];
                        rec.invitationDate = [dateFormat dateFromString:dateStr];
                        [dateFormat release];
                    }
                    [referrals addObject:rec];
                }
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_QUERY_REFERRAL_COMPLETE object:nil];
        } else {
            errorMessage = [[resp objectForKey:@"desc"] retain];
            [[NSNotificationCenter defaultCenter] postNotificationName:NOTIF_HOOK_QUERY_REFERRAL_FAILED object:nil];
        }
        
        [queryReferralConnection release];
        queryReferralConnection = nil;
    }
    
    if (connection == newInstallConnection) {
        NSString *dataStr = [[[NSString alloc] initWithData:newInstallData encoding:NSUTF8StringEncoding] autorelease];
        NSLog (@"newInstall data is %@", dataStr);
        [newInstallData release];
        
        HKMSBJSON *jsonReader = [[HKMSBJSON new] autorelease];
        NSDictionary *resp = [jsonReader objectWithString:dataStr];
        if ([[resp objectForKey:@"status"] intValue] == 1000) {
            NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
            if (standardUserDefaults) {
                installCode = [[resp objectForKey:@"installCode"] retain];
                [standardUserDefaults setObject:installCode forKey:@"installCode"];
                [standardUserDefaults synchronize];
            }
        }
        [newInstallConnection release];
        newInstallConnection = nil;
    }
}



+ (void) activate:(NSString *)ak {
    if (_agent) {
        return;
    }
    
    _agent = [[HKMDiscoverer alloc] init];
    _agent.server = @"https://age.hookmobile.com";
    _agent.SMSDest = @"3025175040";
    _agent.appKey = ak;
    
    return;
}


+ (void) retire {
    [_agent release];
    _agent = nil;
}

+ (HKMDiscoverer *) agent {
    if (_agent == nil) {
        [NSException raise:@"InstanceNotExists"
                    format:@"Attempted to access instance before initializaion. Please call activate: first."];
    }
    return _agent;
}


@end