// Modified for 3012 from 3105 AppIconHelper.m, GPL-3.0, commit
// 90ab4dd35823d58de10e6b8b78236e0e7e1ad32b.

#import "InstalledAppBridge.h"
#import <dlfcn.h>
#import <objc/message.h>

static NSString *PAString(id object) {
    return [object isKindOfClass:NSString.class] && [object length] ? object : nil;
}

static NSString *PAPath(id object) {
    if ([object isKindOfClass:NSURL.class]) return [object path];
    return PAString(object);
}

static NSDictionary *PAWorkspaceApps(void) {
    Class cls = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultSelector = NSSelectorFromString(@"defaultWorkspace");
    if (!cls || ![cls respondsToSelector:defaultSelector]) return @{};
    id workspace = ((id (*)(id, SEL))objc_msgSend)(cls, defaultSelector);
    NSArray *proxies = nil;
    for (NSString *name in @[@"allInstalledApplications", @"allApplications"]) {
        SEL selector = NSSelectorFromString(name);
        if (![workspace respondsToSelector:selector]) continue;
        id value = ((id (*)(id, SEL))objc_msgSend)(workspace, selector);
        if ([value isKindOfClass:NSArray.class] && [value count]) { proxies = value; break; }
    }
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (id proxy in proxies ?: @[]) {
        SEL bundleSelector = NSSelectorFromString(@"bundleIdentifier");
        NSString *bundleID = [proxy respondsToSelector:bundleSelector]
            ? PAString(((id (*)(id, SEL))objc_msgSend)(proxy, bundleSelector)) : nil;
        if (!bundleID) continue;
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        SEL nameSelector = NSSelectorFromString(@"localizedName");
        NSString *name = [proxy respondsToSelector:nameSelector]
            ? PAString(((id (*)(id, SEL))objc_msgSend)(proxy, nameSelector)) : nil;
        entry[@"name"] = name ?: bundleID;
        for (NSString *selectorName in @[@"dataContainerURL", @"containerURL"]) {
            SEL selector = NSSelectorFromString(selectorName);
            if (![proxy respondsToSelector:selector]) continue;
            NSString *path = PAPath(((id (*)(id, SEL))objc_msgSend)(proxy, selector));
            if (path.length) { entry[@"container"] = path; break; }
        }
        result[bundleID] = entry;
    }
    return result;
}

static NSDictionary *PAMobileInstallationApps(void) {
    void *framework = dlopen(
        "/System/Library/PrivateFrameworks/MobileInstallation.framework/MobileInstallation",
        RTLD_LAZY | RTLD_LOCAL
    );
    void *symbol = dlsym(RTLD_DEFAULT, "MobileInstallationLookup");
    if (!symbol && framework) symbol = dlsym(framework, "MobileInstallationLookup");
    if (!symbol) { if (framework) dlclose(framework); return @{}; }
    NSDictionary *raw = ((NSDictionary *(*)(NSDictionary *, void *))symbol)(
        @{@"ApplicationType": @"Any"}, NULL
    );
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *fallbackID in raw ?: @{}) {
        NSDictionary *info = [raw[fallbackID] isKindOfClass:NSDictionary.class]
            ? raw[fallbackID] : nil;
        NSString *bundleID = PAString(info[@"CFBundleIdentifier"]) ?: fallbackID;
        if (!bundleID.length) continue;
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"name"] = PAString(info[@"CFBundleDisplayName"])
            ?: PAString(info[@"CFBundleName"]) ?: bundleID;
        NSString *path = PAPath(info[@"Container"]) ?: PAPath(info[@"DataContainer"])
            ?: PAPath(info[@"DataContainerURL"]);
        if (path.length) entry[@"container"] = path;
        result[bundleID] = entry;
    }
    if (framework) dlclose(framework);
    return result;
}

NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *PA3012InstalledAppInfo(void) {
    NSDictionary *workspace = PAWorkspaceApps();
    return workspace.count ? workspace : PAMobileInstallationApps();
}
