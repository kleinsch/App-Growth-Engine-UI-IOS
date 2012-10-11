#import <Foundation/Foundation.h>

@interface HKMLead : NSObject {
	
	NSString *phone;
	NSString *osType;
    NSString *name;
    UIImage *image;
    
    int invitationCount;
    NSDate *lastInvitationSent;
    
    BOOL selected;

}

@property (nonatomic, retain) NSString *phone;
@property (nonatomic, retain) NSString *osType;
@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) UIImage *image;
@property (nonatomic) int invitationCount;
@property (nonatomic, retain) NSDate *lastInvitationSent;

@property (nonatomic) BOOL selected;

- (id) init;

@end;