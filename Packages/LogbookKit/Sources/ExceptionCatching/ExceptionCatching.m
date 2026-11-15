#import "ExceptionCatching.h"

NSErrorDomain const LKObjCExceptionErrorDomain = @"codes.tim.LogbookKit.ObjCException";

@implementation LKObjCExceptionCatcher

+ (BOOL)performBlock:(NS_NOESCAPE void (^)(void))block error:(NSError **)error {
  @try {
    block();
    return YES;
  } @catch (NSException *exception) {
    if (error) {
      *error = [NSError errorWithDomain:LKObjCExceptionErrorDomain
                                   code:0
                               userInfo:@{
                                 NSLocalizedFailureReasonErrorKey : exception.name,
                                 NSDebugDescriptionErrorKey : exception.reason ?: @""
                               }];
    }
    return NO;
  }
}

@end
