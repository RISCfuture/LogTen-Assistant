#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The error domain for Objective-C exceptions converted to errors.
FOUNDATION_EXPORT NSErrorDomain const LKObjCExceptionErrorDomain;

/// Converts Objective-C exceptions into Swift errors.
///
/// Swift cannot catch Objective-C exceptions, and some Foundation APIs, such as
/// `+[NSPredicate predicateWithFormat:]`, raise them for invalid input.
NS_SWIFT_NAME(ObjCExceptionCatcher)
@interface LKObjCExceptionCatcher : NSObject

/// Runs a block, converting an Objective-C exception it raises into an error.
///
/// @param block The block to run.
/// @param error On return, the converted exception, if one was raised. Its user info carries
///   the exception's name under `NSLocalizedFailureReasonErrorKey` and its reason under
///   `NSDebugDescriptionErrorKey`.
/// @return YES if the block finished without raising.
+ (BOOL)performBlock:(NS_NOESCAPE void (^)(void))block
               error:(NSError *_Nullable *_Nullable)error NS_SWIFT_NAME(perform(_:));

@end

NS_ASSUME_NONNULL_END
