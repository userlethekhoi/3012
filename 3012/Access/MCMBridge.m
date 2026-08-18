// Modified for 3012 read-only provider integration on 2026-08-18.
// Derived from FilzaSlop MCMBridge at commit ec490ade64b7755544833248d915e4adfc6f80d6.

#import "MCMBridge.h"

#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <stdlib.h>
#import <unistd.h>
#import <xpc/xpc.h>

typedef void *(*MCMQueryCreate)(void);
typedef void (*MCMQuerySetU64)(void *, uint64_t);
typedef void (*MCMQuerySetXPC)(void *, xpc_object_t);
typedef void *(*MCMQueryGetPointer)(void *);
typedef bool (*MCMQueryIterate)(void *, bool (^)(void *));
typedef void (*MCMQueryFree)(void *);
typedef const char *(*MCMObjectGetPath)(void *);
typedef const char *(*MCMObjectGetIdentifier)(void *);
typedef void *(*MCMObjectCopy)(void *);
typedef char *(*MCMObjectCopyToken)(void *);
typedef bool (*MCMObjectActivate)(void *, bool);
typedef void (*MCMObjectFree)(void *);
typedef int (*MCMErrorGetInt)(void *);
typedef const char *(*MCMErrorGetString)(void *);

typedef struct {
    void *handle;
    MCMQueryCreate queryCreate;
    MCMQuerySetU64 querySetClass;
    MCMQuerySetXPC querySetIdentifiers;
    MCMQuerySetXPC querySetGroupIdentifiers;
    MCMQuerySetU64 querySetFlags;
    MCMQuerySetU64 querySetPart;
    MCMQueryGetPointer queryGetSingle;
    MCMQueryGetPointer queryGetLastError;
    MCMQueryIterate queryIterate;
    MCMQueryFree queryFree;
    MCMObjectGetPath objectGetPath;
    MCMObjectGetIdentifier objectGetIdentifier;
    MCMObjectCopy objectCopy;
    MCMObjectCopyToken objectCopyToken;
    MCMObjectActivate objectActivate;
    MCMObjectFree objectFree;
    MCMErrorGetInt errorGetPOSIX;
    MCMErrorGetString errorGetMessage;
} MCMAPI;

static MCMAPI *MCMSharedAPI(void) {
    static MCMAPI api;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        api.handle = dlopen(
            "/usr/lib/system/libsystem_containermanager.dylib",
            RTLD_NOW | RTLD_LOCAL
        );
        void *handle = api.handle != NULL ? api.handle : RTLD_DEFAULT;
#define LOAD(field, symbol) api.field = (__typeof(api.field))dlsym(handle, symbol)
        LOAD(queryCreate, "container_query_create");
        LOAD(querySetClass, "container_query_set_class");
        LOAD(querySetIdentifiers, "container_query_set_identifiers");
        LOAD(querySetGroupIdentifiers, "container_query_set_group_identifiers");
        LOAD(querySetFlags, "container_query_operation_set_flags");
        LOAD(querySetPart, "container_query_operation_set_part");
        LOAD(queryGetSingle, "container_query_get_single_result");
        LOAD(queryGetLastError, "container_query_get_last_error");
        LOAD(queryIterate, "container_query_iterate_results_sync");
        LOAD(queryFree, "container_query_free");
        LOAD(objectGetPath, "container_object_get_path");
        LOAD(objectGetIdentifier, "container_object_get_identifier");
        LOAD(objectCopy, "container_object_copy");
        LOAD(objectCopyToken, "container_copy_sandbox_token");
        LOAD(objectActivate, "container_object_sandbox_extension_activate");
        LOAD(objectFree, "container_object_free");
        LOAD(errorGetPOSIX, "container_error_get_posix_errno");
        LOAD(errorGetMessage, "container_error_get_message");
#undef LOAD
    });
    return &api;
}

BOOL MCMBridgeAvailable(void) {
    MCMAPI *api = MCMSharedAPI();
    return api->queryCreate != NULL && api->querySetClass != NULL &&
        api->querySetIdentifiers != NULL && api->querySetGroupIdentifiers != NULL &&
        api->querySetFlags != NULL && api->queryGetSingle != NULL &&
        api->queryGetLastError != NULL && api->queryFree != NULL &&
        api->objectGetPath != NULL && api->objectCopy != NULL &&
        api->objectCopyToken != NULL && api->objectActivate != NULL &&
        api->objectFree != NULL;
}

static NSString *MCMErrorDescription(MCMAPI *api, void *query, NSString *fallback) {
    void *queryError = api->queryGetLastError ? api->queryGetLastError(query) : NULL;
    int posix = queryError && api->errorGetPOSIX ? api->errorGetPOSIX(queryError) : 0;
    const char *message = queryError && api->errorGetMessage
        ? api->errorGetMessage(queryError) : NULL;
    return [NSString stringWithFormat:@"%@ posix=%d message=%s",
        fallback, posix, message ?: "unknown"];
}

NSArray<NSString *> *MCMEnumerateIdentifiersForClass(
    uint64_t containerClass,
    NSUInteger limit,
    NSString **error
) {
    MCMAPI *api = MCMSharedAPI();
    if (!MCMBridgeAvailable() || !api->queryIterate ||
        !api->objectGetIdentifier || limit == 0) {
        if (error) *error = @"ContainerManager enumeration API unavailable";
        return @[];
    }
    void *query = api->queryCreate();
    if (!query) {
        if (error) *error = @"container_query_create returned NULL";
        return @[];
    }
    api->querySetClass(query, containerClass);
    api->querySetFlags(query, 0x100000000ULL);
    if (api->querySetPart) api->querySetPart(query, 0);

    NSMutableOrderedSet<NSString *> *identifiers = [NSMutableOrderedSet orderedSet];
    BOOL iterated = api->queryIterate(query, ^bool(void *object) {
        const char *raw = object ? api->objectGetIdentifier(object) : NULL;
        NSString *identifier = raw ? [NSString stringWithUTF8String:raw] : nil;
        if (identifier.length) [identifiers addObject:identifier];
        return identifiers.count < limit;
    });
    if (!iterated && identifiers.count < limit && error) {
        *error = MCMErrorDescription(api, query, @"enumeration denied");
    }
    api->queryFree(query);
    return identifiers.array;
}

static BOOL MCMSafeIdentifier(NSString *identifier) {
    if (identifier.length == 0 || identifier.length > 255) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"];
    return [identifier rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound &&
        ![identifier isEqualToString:@"."] && ![identifier isEqualToString:@".."];
}

@interface MCM3012Lease : NSObject {
    void *_query;
    void *_activation;
}
@property(nonatomic, copy) NSString *rootPath;
@property(nonatomic) BOOL activated;
+ (nullable instancetype)leaseForClass:(uint64_t)containerClass
                             identifier:(NSString *)identifier
                                  group:(BOOL)group
                                  error:(NSString **)error;
- (BOOL)activate:(NSString **)error;
@end

@implementation MCM3012Lease

+ (instancetype)leaseForClass:(uint64_t)containerClass
                    identifier:(NSString *)identifier
                         group:(BOOL)group
                         error:(NSString **)error {
    MCMAPI *api = MCMSharedAPI();
    if (!MCMBridgeAvailable() || !MCMSafeIdentifier(identifier)) {
        if (error) *error = @"MCM unavailable or identifier invalid";
        return nil;
    }
    void *query = api->queryCreate();
    if (!query) {
        if (error) *error = @"container_query_create returned NULL";
        return nil;
    }
    api->querySetClass(query, containerClass);
    xpc_object_t value = xpc_string_create(identifier.UTF8String);
    if (group) api->querySetGroupIdentifiers(query, value);
    else api->querySetIdentifiers(query, value);
#if !OS_OBJECT_USE_OBJC
    xpc_release(value);
#endif
    api->querySetFlags(query, 0x900000000ULL);
    if (api->querySetPart) api->querySetPart(query, 0);

    void *object = api->queryGetSingle(query);
    if (!object) {
        if (error) *error = MCMErrorDescription(api, query, @"lookup denied");
        api->queryFree(query);
        return nil;
    }
    const char *rawPath = api->objectGetPath(object);
    NSString *root = rawPath ? [NSString stringWithUTF8String:rawPath] : nil;
    if (root.length == 0 || !root.isAbsolutePath) {
        if (error) *error = @"MCM returned no absolute container path";
        api->queryFree(query);
        return nil;
    }
    if ([root isEqualToString:@"/var"] || [root hasPrefix:@"/var/"]) {
        root = [@"/private" stringByAppendingString:root];
    }
    MCM3012Lease *lease = [MCM3012Lease new];
    lease->_query = query;
    lease.rootPath = root;
    return lease;
}

typedef int64_t (*SandboxExtensionConsumeFunc)(const char *extension);

static SandboxExtensionConsumeFunc MCMSandboxExtensionConsume(void) {
    static SandboxExtensionConsumeFunc consumeFunc;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW | RTLD_LOCAL);
        void *symbolHandle = handle != NULL ? handle : RTLD_DEFAULT;
        consumeFunc = (SandboxExtensionConsumeFunc)dlsym(symbolHandle, "sandbox_extension_consume");
    });
    return consumeFunc;
}

- (BOOL)activate:(NSString **)error {
    if (self.activated) return YES;
    MCMAPI *api = MCMSharedAPI();
    void *object = _query ? api->queryGetSingle(_query) : NULL;
    _activation = object ? api->objectCopy(object) : NULL;
    char *token = _activation ? api->objectCopyToken(_activation) : NULL;
    BOOL tokenPresent = token && token[0] != '\0';
    BOOL tokenConsumed = NO;
    if (tokenPresent) {
        SandboxExtensionConsumeFunc consume = MCMSandboxExtensionConsume();
        if (consume) {
            int64_t handle = consume(token);
            tokenConsumed = (handle >= 0);
        }
        free(token);
    }
    BOOL objectActivated = _activation && api->objectActivate ? api->objectActivate(_activation, false) : NO;
    self.activated = tokenConsumed || objectActivated;
    if (!self.activated && error) {
        *error = tokenPresent
            ? @"sandbox extension consume and activation failed"
            : @"MCM object contained no sandbox token";
    }
    return self.activated;
}

- (void)dealloc {
    MCMAPI *api = MCMSharedAPI();
    if (_activation) api->objectFree(_activation);
    if (_query) api->queryFree(_query);
}

@end

static NSMutableDictionary<NSString *, MCM3012Lease *> *MCMActiveLeases(void) {
    static NSMutableDictionary<NSString *, MCM3012Lease *> *leases;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ leases = [NSMutableDictionary dictionary]; });
    return leases;
}

NSString *MCMActivateContainerPath(
    uint64_t containerClass,
    NSString *identifier,
    BOOL groupIdentifier,
    NSString **error
) {
    if (![NSBundle.mainBundle.bundleIdentifier
        isEqualToString:@"com.apple.mobile.MobileHouseArrest"]) {
        if (error) *error = @"host bundle identifier is not MobileHouseArrest";
        return nil;
    }
    if (!MCMSafeIdentifier(identifier)) {
        if (error) *error = @"identifier contains unsupported characters";
        return nil;
    }

    NSMutableDictionary *leases = MCMActiveLeases();
    NSString *key = [NSString stringWithFormat:@"%llu:%d:%@",
        containerClass, groupIdentifier, identifier];
    @synchronized (leases) {
        MCM3012Lease *existing = leases[key];
        if (existing.rootPath.length) return existing.rootPath;

        NSString *detail = nil;
        MCM3012Lease *lease = [MCM3012Lease leaseForClass:containerClass
            identifier:identifier group:groupIdentifier error:&detail];
        if (!lease || ![lease activate:&detail]) {
            if (error) *error = detail ?: @"MCM activation failed";
            return nil;
        }
        int descriptor = open(
            lease.rootPath.fileSystemRepresentation,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        );
        if (descriptor < 0) {
            if (error) *error = [NSString stringWithFormat:
                @"container root open failed errno=%d", errno];
            return nil;
        }
        close(descriptor);
        leases[key] = lease;
        return lease.rootPath;
    }
}
