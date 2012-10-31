//
//  AppDelegate.m
//  ageui
//
//  Created by Kirk Tsai on 10/11/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
// 

#import "AppDelegate.h"

@implementation AppDelegate

@synthesize window = _window;
@synthesize infoLabel = _infoLabel;
- (void)dealloc
{
    [_infoLabel release];
    [_window release];
    [super dealloc];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{    
    self.window = [[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    
    // create a share button
    UIButton *demoBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [demoBtn setTitle:@"Share App" forState:UIControlStateNormal];
    demoBtn.frame = CGRectMake(100, 220, 120, 44);
    [demoBtn addTarget:self action:@selector(showListView) forControlEvents:UIControlEventTouchUpInside];
    [self.window addSubview:demoBtn];
    
    // create a text label to show status returned from invitation
    _infoLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, 320, 30)];
    _infoLabel.textAlignment = UITextAlignmentCenter;
    [self.window addSubview:_infoLabel];
    
    self.window.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)showListView
{
    HKMInviteView *inviteView = [[HKMInviteView alloc] initWithKey:@"b9ef3007-c9a9-459d-977a-a62125cf6b1e"
                                                           title:@"Suggested Contacts" 
                                                    sendBtnLabel:@"Invite"
															  view:self.window];
    inviteView.delegate = self;
    [inviteView showInView:self.window animated:YES];
    [inviteView release];
}

#pragma mark - HKInvite delegates
- (void)invitedCount:(NSInteger)count;
{
    _infoLabel.text = [NSString stringWithFormat:@"You have shared this app with %d friends", count];
}

- (void)inviteCancelled
{
    _infoLabel.text = @"You have cancelled from sharing";
}

@end
