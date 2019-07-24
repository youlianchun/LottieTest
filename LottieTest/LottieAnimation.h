//
//  LottieAnimation.h
//  LottieTest
//
//  Created by YLCHUN on 2019/7/23.
//  Copyright © 2019 YLCHUN. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN BOOL kDebugEnabled;
FOUNDATION_EXPORT void playLottieAnimation(NSString *animation, NSBundle *bundle, CGPoint center, UIView*inView,  void(^ _Nullable completion)(BOOL finished));

NS_ASSUME_NONNULL_END
