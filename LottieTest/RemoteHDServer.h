//
//  RemoteHDServer.h
//  GCDWebHDServer
//
//  Created by YLCHUN on 2019/7/17.
//  Copyright © 2019 YLCHUN. All rights reserved.
//

#import "SingleObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface HDAuthAccount : NSObject
- (void)setObject:(nullable NSString *)obj forKeyedSubscript:(NSString *)key;
- (nullable NSString *)objectForKeyedSubscript:(NSString *)key;
- (void)setPassword:(nullable NSString *)password name:(NSString *)name;
- (nullable NSString *)passwordForName:(NSString *)name;
@end

@interface HDConfig : NSObject
@property (nonatomic, assign) NSUInteger port;
@property (nonatomic, copy) NSString *bonjourName;
@property (nonatomic, copy) NSString *directory;
@end

@interface RemoteHDServer : SingleObject
@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) NSURL *url;
@property (class, nonatomic, readonly) unsigned long long space;

- (void)startWithOption:(void(^)(HDConfig *conf, HDAuthAccount *auth))conf;
- (void)stop;

+ (instancetype)share;
@end

NS_ASSUME_NONNULL_END
