//
//  ViewController.m
//  YKFileCacherDemo
//
//  Created by zhang zhiyu on 13-7-6.
//  Copyright (c) 2013年 York. All rights reserved.
//

#import "ViewController.h"
#import "YKFileCacher.h"

@interface ViewController ()
- (void)processNotification:(NSNotification *)notification;
- (void)updateImageView:(NSString *)imgPath;
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(processNotification:) name:yk_fileCacheDownloadFinishedNotification object:nil];

    NSString *fileUrlStr =@"http://e.hiphotos.baidu.com/album/w%3D2048%3Bq%3D75/sign=a49094618718367aad8978dd1a4bb0a5/b90e7bec54e736d13befd5409a504fc2d46269fd.jpg";

    
    if ([[YKFileCacher sharedCacher] hasCachedFile:fileUrlStr]) {
        [self updateImageView:fileUrlStr];
    }else{
        [[YKFileCacher sharedCacher] addFileCacheTask:fileUrlStr];
    }    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:yk_fileCacheDownloadFinishedNotification object:nil];
    
    [super dealloc];
}

- (void)updateImageView:(NSString *)imgPath
{
    NSString *filePath = [[YKFileCacher sharedCacher] pathInCurrentCacheDirectory:imgPath];

    UIImageView *imgView = (UIImageView *)[self.view viewWithTag:300];
    
    imgView.image = [UIImage imageWithContentsOfFile:filePath];
}

- (void)processNotification:(NSNotification *)notification
{
    NSString *name = notification.name;

    if ([name isEqualToString:yk_fileCacheDownloadFinishedNotification]) {
        NSDictionary *userInfo = notification.userInfo;

        BOOL result = [[userInfo objectForKey:@"result"] boolValue];
        
        if (result) {
            NSString *fileUrlStr = [userInfo objectForKey:@"resultInfo"];
            NSLog(@"filePath:%@",fileUrlStr);
            
            [self performSelectorOnMainThread:@selector(updateImageView:) withObject:fileUrlStr waitUntilDone:NO];
        }
    }
}

@end
