//
//  ViewController.m
//  LottieTest
//
//  Created by YLCHUN on 2019/7/24.
//  Copyright © 2019 YLCHUN. All rights reserved.
//

#import "ViewController.h"
#import "RemoteHDServer.h"
#import "LottieAnimation.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UILabel *pathLabel;
@property (nonatomic, strong) UITapGestureRecognizer *doubleTapGesture;
@property (nonatomic, strong) NSString *path;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.pathLabel.textColor = [UIColor whiteColor];
    [self.view addGestureRecognizer:self.doubleTapGesture];

    // Do any additional setup after loading the view.
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (IBAction)debugSwitchAction:(UISwitch *)sender {
    kDebugEnabled = sender.on;
}

- (IBAction)switchAction:(UISwitch *)sender {
    if (sender.on) {
        [[RemoteHDServer share] startWithOption:^(HDConfig * _Nonnull conf, HDAuthAccount * _Nonnull auth) {
            conf.directory = self.path;
            conf.port = 8899;
        }];
    } else {
        [[RemoteHDServer share] stop];
    }
    sender.on = [RemoteHDServer share].running;
    self.pathLabel.text = [RemoteHDServer share].url.absoluteString;
    if (self.pathLabel.text.length == 0) {
        self.pathLabel.text = @"http://";
    }
}

- (UITapGestureRecognizer *)doubleTapGesture {
    if (!_doubleTapGesture) {
        _doubleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapGestureHandler:)];
        _doubleTapGesture.numberOfTapsRequired = 2;
        _doubleTapGesture.numberOfTouchesRequired = 1;
    }
    return _doubleTapGesture;
}

- (void)doubleTapGestureHandler:(UITapGestureRecognizer *)sender {
    NSString *animation;
    NSArray *arr = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.path error:NULL];
    for (NSString *name in arr) {
        if ([name hasSuffix:@".json"]) {
            animation = name;
            break;
        }
    }
    if (!animation) return;
    
    CGPoint point = [sender locationInView:sender.view];
    NSBundle *build = [NSBundle bundleWithPath:self.path];
    playLottieAnimation(animation, build, point, self.view, nil);
}

- (NSString *)path {
    if (!_path) {
        _path = documentPath(@"LottieAnimation");
    }
    return _path;
}

static NSString *documentPath(NSString *component) {
    NSString *document = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *path = [document stringByAppendingPathComponent:component];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDir = NO;
    BOOL existed = [fileManager fileExistsAtPath:path isDirectory:&isDir];
    if (!isDir || !existed) {
        [fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return path;
}

@end
