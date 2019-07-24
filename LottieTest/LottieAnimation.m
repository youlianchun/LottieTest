//
//  LottieAnimation.m
//  LottieTest
//
//  Created by YLCHUN on 2019/7/23.
//  Copyright © 2019 YLCHUN. All rights reserved.
//

#import "LottieAnimation.h"
#import <Lottie/Lottie.h>

BOOL kDebugEnabled = NO;

static void debugAnimationArea(UIView *animationView) {
    UIBezierPath *p = [[UIBezierPath alloc] init];
    [p moveToPoint:CGPointZero];
    [p addLineToPoint:CGPointMake(animationView.bounds.size.width, animationView.bounds.size.height)];
    [p moveToPoint:CGPointMake(0, animationView.bounds.size.height)];
    [p addLineToPoint:CGPointMake(animationView.bounds.size.width, 0)];
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.frame = animationView.bounds;
    layer.borderWidth = 1;
    layer.borderColor = [UIColor redColor].CGColor;
    layer.path = p.CGPath;
    layer.lineWidth = layer.borderWidth;
    layer.strokeColor = layer.borderColor;
    layer.lineDashPattern = @[@(2), @(4)];
    [animationView.layer addSublayer:layer];
}

void playLottieAnimation(NSString *animation, NSBundle *bundle, CGPoint center, UIView*inView,  void(^completion)(BOOL finished)) {
    if (!inView || animation.length == 0) {
        return ;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSBundle *inBundle = bundle?bundle:[NSBundle mainBundle];
        LOTAnimationView *animationView = [LOTAnimationView animationNamed:animation inBundle:inBundle];
        if (!animationView) return ;
        if (kDebugEnabled) {
            debugAnimationArea(animationView);
        }
        animationView.userInteractionEnabled = YES;
        animationView.contentMode = UIViewContentModeCenter;
        animationView.backgroundColor = [UIColor clearColor];
        animationView.center = center;
        [inView addSubview:animationView];
        __weak typeof(animationView) weak_animationView = animationView;
        [animationView playWithCompletion:^(BOOL animationFinished) {
            [weak_animationView removeFromSuperview];
            !completion ?: completion(animationFinished);
        }];
    });
}

