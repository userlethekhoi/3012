// Modified for 3012 read-only provider integration on 2026-08-18.
// Derived from FilzaSlop MCMBridge at commit ec490ade64b7755544833248d915e4adfc6f80d6.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT BOOL MCMBridgeAvailable(void);
FOUNDATION_EXPORT NSArray<NSString *> *MCMEnumerateIdentifiersForClass(
    uint64_t containerClass,
    NSUInteger limit,
    NSString * _Nullable * _Nullable error
);
FOUNDATION_EXPORT NSString * _Nullable MCMActivateContainerPath(
    uint64_t containerClass,
    NSString *identifier,
    BOOL groupIdentifier,
    NSString * _Nullable * _Nullable error
);

NS_ASSUME_NONNULL_END
