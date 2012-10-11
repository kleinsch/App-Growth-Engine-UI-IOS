@protocol HKInviteDelegate;
@interface HKInviteView : UIView <UITableViewDataSource, UITableViewDelegate>
{
    UITableView *_tableView;
    UIButton *_sendButton;
    NSString *_title;
    NSTimer *_aTimer;
    BOOL _firstUse;
    int _lastInviteCount;
}

@property (nonatomic, assign) id<HKInviteDelegate> delegate;

- (id)initWithKey: (NSString *)apiKey title:(NSString *)aTitle sendBtnLabel:(NSString *)sendBtnLabel;
- (void)showInView:(UIView *)aView animated:(BOOL)animated;
- (void)registerNotification; 

@end

@protocol HKInviteDelegate <NSObject>
- (void)invitedCount:(NSInteger)count;
- (void)inviteCancelled;
@end