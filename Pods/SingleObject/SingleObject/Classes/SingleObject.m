//
//  SingleObject.m
//  SingleObject
//
//  Created by YLCHUN on 2018/3/28.
//  Copyright © 2018年 YLCHUN. All rights reserved.
//

#import "SingleObject.h"
#import <pthread.h>
#import <objc/runtime.h>

@implementation SingleObject
{
   @private bool _initToken;
}

+(instancetype)allocWithZone:(struct _NSZone *)zone
{
#if DEBUG
    if ([class_getSuperclass(self) hash] != [SingleObject hash]) {
        if ([self hash] == [SingleObject hash]) {
            NSCAssert(false, @"\n 使用单例必须从 Singleton 派生.\n");
        }else {
            NSCAssert(false, @"\n %s 必须直接从 Singleton 派生.\n", object_getClassName(self));
        }
    }
#endif
    static pthread_mutex_t allocLock = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&allocLock);
    static char associatedkey;
    id singleton = objc_getAssociatedObject(self, &associatedkey);
    if (!singleton)
    {
        [self _onceInit];
        singleton = [super allocWithZone:zone];
        objc_setAssociatedObject(self, &associatedkey, singleton, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    pthread_mutex_unlock(&allocLock);
    return singleton;
}

+(void)_onceInit
{
    SEL sel = @selector(init);
    IMP init = class_getMethodImplementation(self, sel);
    IMP block = imp_implementationWithBlock(^id(SingleObject *self) {
        static pthread_mutex_t initLock = PTHREAD_MUTEX_INITIALIZER;
        pthread_mutex_lock(&initLock);
        if (!self->_initToken) {
            self->_initToken = true;
            self = ((id(*)(id, SEL))init)(self, sel);
        }
        pthread_mutex_unlock(&initLock);
        return self;
    });
    class_replaceMethod(self, sel, block, "@:");
}

-(id)copyWithZone:(NSZone *)zone {
    return self;
}

-(id)mutableCopyWithZone:(NSZone *)zone {
    return self;
}

@end
