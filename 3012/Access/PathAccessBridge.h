// Path-scoped Device Access bridge for 3012.
// Derived from 3105 bad_query.c at commit 90ab4dd35823d58de10e6b8b78236e0e7e1ad32b.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT int64_t PA3012GrantPath(NSString *path);
FOUNDATION_EXPORT void PA3012ReleaseGrant(int64_t handle);
FOUNDATION_EXPORT NSArray<NSString *> *PA3012DirectoryNames(
    NSString *path,
    NSUInteger limit,
    int64_t * _Nullable retainedHandle,
    NSString * _Nullable * _Nullable error
);

NS_ASSUME_NONNULL_END
