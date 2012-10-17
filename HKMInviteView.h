#define ADDRESSBOOK_DENIED_ACCESS_ALERT_TITLE @"Whoops!"
#define ADDRESSBOOK_DENIED_ACCESS_ALERT_MSG  @"To share this app with your friends, we need access to your address book. Please go to Settings / Privacy / Contacts and enable access for this app."
#define INVITE_SELECT_SOME_FRIENDS_MSG @"Please select a few friends first"
#define NO_NETWORK_COVERAGE_ERROR_ALERT_TITLE @"Sorry!"
#define NO_NETWORK_COVERAGE_ERROR_ALERT_MSG @"No data coverage. Please check your settings"

@protocol HKMInviteDelegate;
@interface HKMInviteView : UIView <UITableViewDataSource, UITableViewDelegate>
{
    UITableView *_tableView;
    UIButton *_sendButton;
    NSString *_title;
    NSTimer *_aTimer;
    BOOL _firstUse;
    int _lastInviteCount;
}

@property (nonatomic, assign) id<HKMInviteDelegate> delegate;

- (id)initWithKey: (NSString *)apiKey title:(NSString *)aTitle sendBtnLabel:(NSString *)sendBtnLabel;
- (void) launchWithPermissionCheck;
- (void)showInView:(UIView *)aView animated:(BOOL)animated;
- (void)registerNotification;

@end

@protocol HKMInviteDelegate <NSObject>
- (void)invitedCount:(NSInteger)count;
- (void)inviteCancelled;
@end