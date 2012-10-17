
#import <AddressBook/AddressBook.h>
#import "HKMInviteView.h"
#import "HKMInviteViewCell.h"
#import "HKMDiscoverer.h"
#import "HKMLead.h"
#import "MBProgressHUD.h"
#import "ODRefreshControl.h"

#define POPLISTVIEW_SCREENINSET 40.
#define POPLISTVIEW_BUTTONINSET 10.
#define POPLISTVIEW_HEADER_HEIGHT 50.
#define POPLISTVIEW_FOOTER_HEIGHT 50.
#define RADIUS 5.
#define FIRST_USE_WAIT_TIME 5.

@interface HKMInviteView (private)
- (void)fadeIn;
- (void)fadeOut;
@end

@implementation HKMInviteView
@synthesize delegate;

#pragma mark - initialization & cleaning up
- (id)initWithKey:(NSString *)apiKey
            title:(NSString *)aTitle
     sendBtnLabel:(NSString *)sendBtnLabel
{
    NSLog(@"initWithKey invoked %@", self);
    CGRect rect = [[UIScreen mainScreen] applicationFrame];
    if (self = [super initWithFrame:rect])
    {
        self.backgroundColor = [UIColor clearColor];
        _title = [aTitle copy];
        
        // register to receive all AGE notification
        [self registerNotification];
        // activate AGE
        [HKMDiscoverer activate:[apiKey copy]];
        _firstUse = [[HKMDiscoverer agent]installCode] == nil;
        
        // start discovering address book and request IOS6 address book permission
        [self launchWithPermissionCheck];
        
        float tableViewWidth = rect.size.width - 2 * POPLISTVIEW_SCREENINSET;
        float tableViewHeight = rect.size.height - 2 * POPLISTVIEW_SCREENINSET - POPLISTVIEW_HEADER_HEIGHT - POPLISTVIEW_FOOTER_HEIGHT- RADIUS;
        
        _tableView = [[UITableView alloc] initWithFrame:CGRectMake(POPLISTVIEW_SCREENINSET,
                                                                   POPLISTVIEW_SCREENINSET + POPLISTVIEW_HEADER_HEIGHT,
                                                                   tableViewWidth,
                                                                   tableViewHeight)];
        _tableView.separatorColor = [UIColor colorWithWhite:0 alpha:.2];
        _tableView.backgroundColor = [UIColor clearColor];
        _tableView.dataSource = self;
        _tableView.delegate = self;
        
        // add pulldown refresh control
        ODRefreshControl *refreshControl = [[[ODRefreshControl alloc] initInScrollView:_tableView] autorelease];
        [refreshControl addTarget:self action:@selector(dropViewDidBeginRefreshing:) forControlEvents:UIControlEventValueChanged];
        
        [self addSubview:_tableView];
        
        // add invite button
        float buttonWidth = (tableViewWidth-POPLISTVIEW_BUTTONINSET*2);
        float buttonHeight = POPLISTVIEW_FOOTER_HEIGHT-POPLISTVIEW_BUTTONINSET*2;
        _sendButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        [_sendButton addTarget:self
                        action:@selector(sendInviteAction)
              forControlEvents:UIControlEventTouchUpInside];
        [_sendButton setTitle:[sendBtnLabel copy] forState:UIControlStateNormal];
        _sendButton.frame = CGRectMake(POPLISTVIEW_SCREENINSET+POPLISTVIEW_BUTTONINSET, POPLISTVIEW_SCREENINSET + POPLISTVIEW_HEADER_HEIGHT + tableViewHeight + POPLISTVIEW_BUTTONINSET, buttonWidth, buttonHeight);
        [self addSubview:_sendButton];
    }
    return self;
}

- (void)dropViewDidBeginRefreshing:(ODRefreshControl *)refreshControl
{
    double delayInSeconds = 0.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [refreshControl endRefreshing];
    });
    [MBProgressHUD showHUDAddedTo:self animated:YES];
    [[HKMDiscoverer agent] queryLeads];
}

- (void)dealloc
{
    [_title release];
    [_tableView release];
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [super dealloc];
}

#pragma mark - Private Methods
- (void)fadeIn
{
    self.transform = CGAffineTransformMakeScale(1.3, 1.3);
    self.alpha = 0;
    [UIView animateWithDuration:.35 animations:^{
        self.alpha = 1;
        self.transform = CGAffineTransformMakeScale(1, 1);
    }];
    
}
- (void)fadeOut
{
    [UIView animateWithDuration:.35 animations:^{
        self.transform = CGAffineTransformMakeScale(1.3, 1.3);
        self.alpha = 0.0;
    } completion:^(BOOL finished) {
        if (finished) {
            [self removeFromSuperview];
        }
    }];
}

#pragma mark - Instance Methods
- (void)showInView:(UIView *)aView animated:(BOOL)animated
{
    [aView addSubview:self];
    if (animated) {
        [self fadeIn];
    }
}

#pragma mark - Tableview datasource & delegates
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([HKMDiscoverer agent].leads != nil) {
        return [[HKMDiscoverer agent].leads count];
    } else {
        return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellIdentity = @"HKINviteViewCell";
    
    HKMInviteViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentity];
    if (cell ==  nil) {
        cell = [[[HKMInviteViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentity] autorelease];
    }
    
    HKMLead *lead = (HKMLead *)[[HKMDiscoverer agent].leads objectAtIndex:indexPath.row];
    cell.textLabel.text = lead.name;
    cell.detailTextLabel.text = lead.osType;
    cell.imageView.image = (lead.image) ? lead.image : [UIImage imageNamed:@"contact.png"];
    
    if (lead.selected) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    HKMLead *lead = [[HKMDiscoverer agent].leads objectAtIndex:indexPath.row];
    if (lead.selected) {
        lead.selected = NO;
    } else {
        lead.selected = YES;
    }
    [_tableView reloadData];
}

#pragma mark - TouchTouchTouch
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    // tell the delegate the cancellation
    if (self.delegate && [self.delegate respondsToSelector:@selector(inviteCancelled)]) {
        [self.delegate inviteCancelled];
    }
    
    
    // dismiss self
    [self fadeOut];
    
}

#pragma mark - DrawDrawDraw
- (void)drawRect:(CGRect)rect
{
    CGRect bgRect = CGRectInset(rect, POPLISTVIEW_SCREENINSET, POPLISTVIEW_SCREENINSET);
    CGRect titleRect = CGRectMake(POPLISTVIEW_SCREENINSET + 10, POPLISTVIEW_SCREENINSET + 10 + 5,
                                  rect.size.width -  2 * (POPLISTVIEW_SCREENINSET + 10), 30);
    CGRect separatorRect = CGRectMake(POPLISTVIEW_SCREENINSET, POPLISTVIEW_SCREENINSET + POPLISTVIEW_HEADER_HEIGHT - 2,
                                      rect.size.width - 2 * POPLISTVIEW_SCREENINSET, 2);
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    // Draw the background with shadow
    CGContextSetShadowWithColor(ctx, CGSizeZero, 6., [UIColor colorWithWhite:0 alpha:.75].CGColor);
    [[UIColor colorWithWhite:0 alpha:.75] setFill];
    
    
    float x = POPLISTVIEW_SCREENINSET;
    float y = POPLISTVIEW_SCREENINSET;
    float width = bgRect.size.width;
    float height = bgRect.size.height;
    CGMutablePathRef path = CGPathCreateMutable();
	CGPathMoveToPoint(path, NULL, x, y + RADIUS);
	CGPathAddArcToPoint(path, NULL, x, y, x + RADIUS, y, RADIUS);
	CGPathAddArcToPoint(path, NULL, x + width, y, x + width, y + RADIUS, RADIUS);
	CGPathAddArcToPoint(path, NULL, x + width, y + height, x + width - RADIUS, y + height, RADIUS);
	CGPathAddArcToPoint(path, NULL, x, y + height, x, y + height - RADIUS, RADIUS);
	CGPathCloseSubpath(path);
	CGContextAddPath(ctx, path);
    CGContextFillPath(ctx);
    CGPathRelease(path);
    
    // Draw the title and the separator with shadow
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1), 0.5f, [UIColor blackColor].CGColor);
    [[UIColor colorWithRed:0.020 green:0.549 blue:0.961 alpha:1.] setFill];
    [_title drawInRect:titleRect withFont:[UIFont systemFontOfSize:20.]];
    CGContextFillRect(ctx, separatorRect);
}

#pragma mark - UI interaction
- (void)sendInviteAction {
    _lastInviteCount = 0;
    NSMutableArray *phones = [[NSMutableArray arrayWithCapacity:16] retain];
    for (HKMLead *lead in [HKMDiscoverer agent].leads) {
        if (lead.selected) {
            [phones addObject:lead.phone];
            _lastInviteCount++;
        }
    }
    if ([phones count] > 0) {
        [[HKMDiscoverer agent] newReferral:phones withName:nil useVirtualNumber:YES];
    } else {
        MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self animated:YES];
        hud.mode = MBProgressHUDModeText;
        hud.labelText = INVITE_SELECT_SOME_FRIENDS_MSG;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [MBProgressHUD hideHUDForView:self animated:YES];
        });
    }
}

#pragma mark - AGE address book handling functions
- (void) launchWithPermissionCheck
{
    ABAddressBookRef ab = ABAddressBookCreate();
    if (ABAddressBookRequestAccessWithCompletion != NULL) {
        ABAddressBookRequestAccessWithCompletion(ab, ^(bool granted, CFErrorRef error) {
            if (granted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [MBProgressHUD showHUDAddedTo:self animated:YES];
                    [[HKMDiscoverer agent] discover:0];
                });
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertView* alert = [[UIAlertView alloc] init];
                    alert.title = ADDRESSBOOK_DENIED_ACCESS_ALERT_TITLE;
                    alert.message = ADDRESSBOOK_DENIED_ACCESS_ALERT_MSG;
                    [alert addButtonWithTitle:@"Dismiss"];
                    alert.cancelButtonIndex = 0;
                    [alert show];
                    [alert release];
                });
            }
        });
    } else {
        // iOS 5
        [MBProgressHUD showHUDAddedTo:self animated:YES];
        [[HKMDiscoverer agent] discover:0];
    }
}


// register for notification of AGE related callback events
- (void)registerNotification
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(discoverCompleted) name:NOTIF_HOOK_DISCOVER_COMPLETE object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(discoverCompleted) name:NOTIF_HOOK_DISCOVER_NO_CHANGE object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(discoverFailed) name:NOTIF_HOOK_DISCOVER_FAILED object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(queryLeadsCompleted) name:NOTIF_HOOK_QUERY_ORDER_COMPLETE object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(queryLeadsFailed) name:NOTIF_HOOK_QUERY_ORDER_FAILED object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkError) name:NOTIF_HOOK_NETWORK_ERROR object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sendReferralCompleted) name:NOTIF_HOOK_NEW_REFERRAL_COMPLETE object:nil];
}

- (void) discoverCompleted
{
    if (_firstUse) {
        _aTimer = [NSTimer scheduledTimerWithTimeInterval:FIRST_USE_WAIT_TIME
                                                   target:self
                                                 selector:@selector(timerFired:)
                                                 userInfo:nil
                                                  repeats:NO];
    } else {
        [[HKMDiscoverer agent] queryLeads];
    }
}

- (void) discoverFailed {
    [MBProgressHUD hideHUDForView:self animated:YES];
    [self fadeOut];
}

-(void)timerFired:(NSTimer *) theTimer
{
    NSLog(@"timerFired @ %@", [theTimer fireDate]);
    BOOL status = [[HKMDiscoverer agent] queryLeads];
    NSLog(@"timerFired - queryLeads status=%d", status);
}

- (void) queryLeadsCompleted
{
    [_tableView reloadData];
    [MBProgressHUD hideHUDForView:self animated:YES];
}

- (void) queryLeadsFailed
{
    [MBProgressHUD hideHUDForView:self animated:YES];
    [self fadeOut];
}

- (void) sendReferralCompleted
{
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self animated:YES];
    hud.mode = MBProgressHUDModeText;
    hud.labelText = @"Invitation Sent!";
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [MBProgressHUD hideHUDForView:self animated:YES];
        // tell the delegate the selection
        if (self.delegate && [self.delegate respondsToSelector:@selector(invitedCount:)]) {
            [self.delegate invitedCount:_lastInviteCount];
        }
        
        [self fadeOut];
    });
}

- (void) networkError
{
    NSLog(@"networkError invoked");
    [MBProgressHUD hideHUDForView:self animated:YES];
    
    UIAlertView* alert = [[UIAlertView alloc] init];
	alert.title = NO_NETWORK_COVERAGE_ERROR_ALERT_TITLE;
	alert.message = NO_NETWORK_COVERAGE_ERROR_ALERT_MSG;
	[alert addButtonWithTitle:@"OK"];
	alert.cancelButtonIndex = 0;
	[alert show];
	[alert release];
    
    [self fadeOut];
}

@end
