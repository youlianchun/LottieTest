//
//  RemoteHDServer.m
//  GCDWebHDServer
//
//  Created by YLCHUN on 2019/7/17.
//  Copyright © 2019 YLCHUN. All rights reserved.
//

#import "RemoteHDServer.h"
#import "GCDWebHDServer.h"
#import <sys/mount.h>

@implementation HDAuthAccount
{
    NSMutableDictionary *_authAccounts;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _authAccounts = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)setPassword:(NSString *)password name:(NSString *)name {
    _authAccounts[name] = password;
}

- (NSString *)passwordForName:(NSString *)name {
    return _authAccounts[name];
}

- (void)setObject:(nullable NSString *)obj forKeyedSubscript:(NSString *)key {
    [self setPassword:obj name:key];
}

- (nullable NSString *)objectForKeyedSubscript:(NSString *)key {
    return [self passwordForName:key];
}

- (NSUInteger)count {
    return _authAccounts.count;
}

- (NSDictionary *)accounts {
    return [_authAccounts copy];
}

@end

#pragma mark -

@implementation HDConfig
@end

#pragma mark -

@implementation RemoteHDServer
{
    GCDWebHDServer * _hdServer;
}

- (instancetype)init {
    if (self = [super init]) {
        _hdServer = [[GCDWebHDServer alloc] init];
        _hdServer.allowHiddenItems = YES;
        _hdServer.delegate = (id<GCDWebHDServerDelegate>)self;
        [GCDWebHDServer setLogLevel:5];
    }
    return self;
}


- (void)startWithOption:(void(^)(HDConfig *conf, HDAuthAccount *auth))conf {
    if (self.running) return;
    [_hdServer startWithOptions:[self optionsWithConf:conf] error:NULL];
}

- (NSDictionary *)optionsWithConf:(void(^)(HDConfig *conf, HDAuthAccount *auth))optionConf {
    HDConfig* conf = [HDConfig new];
    conf.port = 8888;
    conf.bonjourName = NSStringFromClass(self.class);
    conf.directory = NSHomeDirectory();
    HDAuthAccount *account = [HDAuthAccount new];
    !optionConf?:optionConf(conf, account);
    NSMutableDictionary* options = [NSMutableDictionary dictionary];
    options[GCDWebServerOption_Port] = @(conf.port);
    options[GCDWebServerOption_BonjourName] = conf.bonjourName;
    options[GCDWebHDServerOption_HDDirectory] = conf.directory;
    if (account.count > 0) {
        options[GCDWebServerOption_AuthenticationAccounts] = [account accounts];
        options[GCDWebServerOption_AuthenticationMethod] = GCDWebServerAuthenticationMethod_DigestAccess;
    }
    return options;
}

- (void)stop {
    if (!self.running) return;
    [_hdServer stop];
}

- (BOOL)running {
    return _hdServer.running;
}

- (NSURL *)url {
    return _hdServer.serverURL;
}


+ (unsigned long long)space {
    struct statfs buf;
    unsigned long long space = -1;
    if (statfs("/var", &buf) >= 0) {
        space = (unsigned long long)(buf.f_bsize * buf.f_bavail);
    }
    return space;
}

+ (instancetype)share {
    return [self new];
}

@end


@interface RemoteHDServer(delegate)<GCDWebHDServerDelegate>
@end

@implementation GCDWebHDServer (delegate)

- (void)hdServer:(GCDWebHDServer*)server didDownloadFileAtPath:(NSString*)path {
    NSLog(@"%s", __func__);
}

- (void)hdServer:(GCDWebHDServer*)server didUploadFileAtPath:(NSString*)path {
    NSLog(@"%s", __func__);
}

- (void)hdServer:(GCDWebHDServer*)server didMoveItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath {
    NSLog(@"%s", __func__);
}

- (void)hdServer:(GCDWebHDServer*)server didCopyItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath {
    NSLog(@"%s", __func__);
}

- (void)hdServer:(GCDWebHDServer*)server didDeleteItemAtPath:(NSString*)path {
    NSLog(@"%s", __func__);
}

- (void)hdServer:(GCDWebHDServer*)server didCreateDirectoryAtPath:(NSString*)path {
    NSLog(@"%s", __func__);
}

@end
