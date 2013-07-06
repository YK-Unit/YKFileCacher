//
//  YKFileCacher.m
//  YKFileCacherDemo
//
//  Created by zhang zhiyu on 13-7-6.
//  Copyright (c) 2013年 York. All rights reserved.
//

#import "YKFileCacher.h"
#import <objc/runtime.h>
#import <libkern/OSAtomic.h>
#import "NSString+Hash.h"
#import "Reachability.h"

NSString *const yk_networkDisconnectNotification = @"YK_NETWORKDISCONNECT";
NSString *const yk_fileCacheDownloadFinishedNotification = @"YK_FILECACHEDOWNLOADFINISHED";
NSString *const YK_PARSERQUEUE_TAG = @"yk_parserQueue_tag";
static NSInteger yk_parserQueue_key;

#define DEFAULT_YK_HTTPREQUEST_TIMEOUT 20
#define DEFAULT_YK_FILECACHE_DIRECTORY @"com.york.unit"

typedef enum _YK_HTTPRequestMethodType
{
    METHOD_downloadCacheFile,
}YK_HTTPRequestMethodType;

@interface YKFileCacher(Private)
#pragma mark - private methods for manger directory and filePath
- (BOOL)createCacheDirectory:(NSString *)directoryName;
- (BOOL)removeCacheDirectory:(NSString *)directoryName;
- (NSString *)pathOfFile:(NSString *)fileUrlStr InCacheDirectory:(NSString *)cacheDirectory;
- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)contents attributes:(NSDictionary *)attributes;

#pragma mark - private methods for ASIHTTPRequest
/**
 *	@brief	General ASIHTTPRequest result delegate.
 *
 *	@param 	request
 *	@param 	request
 */
- (void)requestFinished:(ASIHTTPRequest *)request;
- (void)requestFailed:(ASIHTTPRequest *)request;


/**
 *	@brief	Stop all processing request;
 */
- (void)stopAllRequest;

/**
 *	@brief	Remove request from request quene;
 */
- (void)removeRequest:(NSString *)timestamp;

/**
 *	@brief	Add request to request quene;
 */
- (void)addRequest:(ASIHTTPRequest *)request wihtKey:(NSString *)timestamp;

/**
 *	@brief	Check the network statue when ASIHTTPRequest fail.
 */
- (void)checkNetworkStatus;

/**
 * This method asynchronously invokes the given block (dispatch_async) on the queue.
 *
 **/
- (void)scheduleBlock:(dispatch_block_t)block;

/**
 *	@brief	Porcess error wiht request error
 *
 *	@param 	request 	ASIHTTPRequest
 *	@param 	name 	notification name for example 'registerNotification'.
 */
- (void)processRequestErrorWithReqs:(ASIHTTPRequest *)request notificationName:(NSString *)name;

- (void)processHttpResponse_downloadCacheFile:(NSInteger)finishType withRequest:(ASIHTTPRequest *)request;
@end

@implementation YKFileCacher
@synthesize requestTimeout,cacheDirectory;
@synthesize processingRequests;

static YKFileCacher *_ykFileCacher = nil;
+ (YKFileCacher *)sharedCacher
{
    if (!_ykFileCacher) {
        _ykFileCacher = [[self alloc]init];
    }
    
    return _ykFileCacher;
}

- (id)init
{
    if (_ykFileCacher) {
        return _ykFileCacher;
    }else{
        self =[super init];
        
        parserQueue = dispatch_queue_create(class_getName([self class]), NULL);
        
        self.processingRequests = [NSMutableDictionary dictionaryWithCapacity:5];
        self.requestTimeout = DEFAULT_YK_HTTPREQUEST_TIMEOUT;
        [self setCacheDirectory:DEFAULT_YK_FILECACHE_DIRECTORY];
        return self;
    }
}

- (void)dealloc
{
    [self stopAllRequest];

    if (parserQueue)
	{
		dispatch_release(parserQueue);
	}
    
    [super dealloc];
}

#pragma mark - cacheDirectory set accessor
- (void)setCacheDirectory:(NSString *)newCacheDirectory
{
    if (cacheDirectory && [cacheDirectory isEqualToString:newCacheDirectory]) {
        return;
    }else{
        if (cacheDirectory) {
            //删除旧的缓存文件夹
            BOOL flag = [self removeCacheDirectory:cacheDirectory];
            NSAssert(flag, @"delete cacheDirectory failed");
        }
        
        //创建新的缓存文件夹
        BOOL flag = [self createCacheDirectory:newCacheDirectory];
        NSAssert(flag, @"create cacheDirectory failed");
        cacheDirectory = [newCacheDirectory copy];
    }
}

#pragma mark - private methods for manger directory and filePath
- (BOOL)createCacheDirectory:(NSString *)directoryName
{
    //获取沙盒中缓存文件目录
    NSArray *cacheDirectories =  NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *localCacheDirectory = [cacheDirectories objectAtIndex:0];
    
    NSString *yourCacheDirectoryPath = [localCacheDirectory stringByAppendingPathComponent:directoryName];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:yourCacheDirectoryPath]) {
        return YES;
    }
    
   return [[NSFileManager defaultManager] createDirectoryAtPath:yourCacheDirectoryPath withIntermediateDirectories:YES attributes:nil error:nil];
}

- (BOOL)removeCacheDirectory:(NSString *)directoryName
{
    //获取沙盒中缓存文件目录
    NSArray *cacheDirectories =  NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *localCacheDirectory = [cacheDirectories objectAtIndex:0];
    
    NSString *yourCacheDirectoryPath = [localCacheDirectory stringByAppendingPathComponent:directoryName];
    
    return [[NSFileManager defaultManager] removeItemAtPath:yourCacheDirectoryPath error:nil];
}

- (NSString *)pathOfFile:(NSString *)fileUrlStr InCacheDirectory:(NSString *)directoryName
{
    //获取沙盒中缓存文件目录
    NSArray *cacheDirectories =  NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *localCacheDirectory = [cacheDirectories objectAtIndex:0];
    
    NSString *fileName = [fileUrlStr md5];
    return [localCacheDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/yk-%@",directoryName,fileName]];
}

- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)contents attributes:(NSDictionary *)attributes
{
    NSFileManager *fileManager=[NSFileManager defaultManager];
    return [fileManager createFileAtPath:path contents:contents attributes:attributes];
}

- (BOOL)createFileInCurrentCacheDirectory:(NSString *)fileUrlStr contents:(NSData *)contents attributes:(NSDictionary *)attributes
{
    NSString *filePath = [self pathOfFile:fileUrlStr InCacheDirectory:cacheDirectory];
    NSLog(@"filePath:%@",filePath);
    return [self createFileAtPath:filePath contents:contents attributes:attributes];
}

#pragma mark -
#pragma mark - ASIHTTPRequest result delegate
- (void)requestFinished:(ASIHTTPRequest *)request
{
    YK_HTTPRequestMethodType method = [(NSNumber *)[request.userInfo objectForKey:@"method"] intValue];
    switch (method) {
        case METHOD_downloadCacheFile:
            [self processHttpResponse_downloadCacheFile:0 withRequest:request];
            break;
        default:
            break;
    }
}

- (void)requestFailed:(ASIHTTPRequest *)request
{
    YK_HTTPRequestMethodType method = [(NSNumber *)[request.userInfo objectForKey:@"method"] intValue];
    switch (method) {
        case METHOD_downloadCacheFile:
            [self processHttpResponse_downloadCacheFile:1 withRequest:request];
            break;
        default:
            break;
    }
}
#pragma mark - Remove requests from request queue.
- (void)removeRequest:(NSString *)timestamp
{
    @synchronized(self) {
		if (processingRequests) {
			[self.processingRequests removeObjectForKey:timestamp];
		}
	}
}

#pragma mark Add requests to request queue.
- (void)addRequest:(ASIHTTPRequest *)request wihtKey:(NSString *)timestamp
{
    @synchronized(self) {
		if (processingRequests) {
            [self.processingRequests setObject:request forKey:timestamp];
		}
	}
}

#pragma mark Stop requests.
- (void)stopAllRequest
{
    @synchronized(self) {
        for (ASIHTTPRequest *request in [self.processingRequests allValues]) {
            request.delegate = nil;
            [request clearDelegatesAndCancel];
        }
    }
}

#pragma Check the network.
- (void)checkNetworkStatus
{
    if([[Reachability reachabilityForInternetConnection] currentReachabilityStatus] == NotReachable)
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:yk_networkDisconnectNotification object:self userInfo:nil];
    }
}

#pragma Process request error.
- (void)processRequestErrorWithReqs:(ASIHTTPRequest *)request notificationName:(NSString *)name

{
    NSError *localError = nil;
    NSString *timestamp = [request.userInfo objectForKey:@"timestamp"];
    if (request.error.code <= ASIRequestTimedOutErrorType) {
        [self checkNetworkStatus];
    }
    localError = [NSError errorWithDomain:request.error.domain code:request.error.code userInfo:[NSDictionary dictionaryWithObjectsAndKeys:request.error.localizedDescription, NSLocalizedDescriptionKey, nil]];
    NSLog(@"requestError:%@ - %@",timestamp,request.error.localizedDescription);
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO], @"result",localError,@"resultInfo",nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:nil userInfo:userInfo];
}

#pragma mark scheduleBlock
- (void)scheduleBlock:(dispatch_block_t)block
{
	dispatch_async(parserQueue, ^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		
		block();
		
		[pool drain];
	});
}

#pragma mark - ASIHTTPRequest respones handler
- (void)processHttpResponse_downloadCacheFile:(NSInteger)finishType withRequest:(ASIHTTPRequest *)request
{
    [self scheduleBlock:^{
        NSString *timestamp = [request.userInfo objectForKey:@"timestamp"];
        if (!finishType) {
            NSData *fileData = [request responseData];
            NSString *fileUrlStr = [[request.userInfo objectForKey:@"fileUrlStr"] copy];
            NSLog(@"-->%@\n",fileUrlStr);
            BOOL flag = [self createFileInCurrentCacheDirectory:fileUrlStr contents:fileData attributes:nil];
            if (flag) {
                NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], @"result",fileUrlStr,@"resultInfo",nil];
                [[NSNotificationCenter defaultCenter] postNotificationName:yk_fileCacheDownloadFinishedNotification object:nil userInfo:userInfo];
            }
        }
        
        [self removeRequest:timestamp];
    }];
}

#pragma mark - public methods for manger caches
- (BOOL)clearAllCaches
{
    BOOL flag1 = [self removeCacheDirectory:cacheDirectory];
    BOOL flag2 = [self createCacheDirectory:cacheDirectory];
    
    return flag1&&flag2;
}

- (BOOL)hasCachedFile:(NSString *)fileUrlStr
{
    NSString *filePath = [self pathInCurrentCacheDirectory:fileUrlStr];
    
    return [[NSFileManager defaultManager] fileExistsAtPath:filePath];
}

- (NSString *)pathInCurrentCacheDirectory:(NSString *)fileUrlStr
{
    NSString *filePath = [self pathOfFile:fileUrlStr InCacheDirectory:cacheDirectory];
    
    return filePath;
}

- (BOOL)addFileCacheTask:(NSString *)fileUrlStr
{
    //timestamp
    NSDate *nowDate = [NSDate date];
	NSTimeInterval timeInterval = [nowDate timeIntervalSince1970];
    NSString *timestamp = [NSString stringWithFormat:@"%f",timeInterval];
    
    NSURL *url = [NSURL URLWithString:fileUrlStr];
    NSLog(@"http request url:%@",url);
    
    ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:url];
    request.requestMethod = @"GET";
    request.delegate = self;
    request.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:METHOD_downloadCacheFile],@"method",timestamp,@"timestamp",fileUrlStr,@"fileUrlStr", nil];
    [request setCacheStoragePolicy:ASICachePermanentlyCacheStoragePolicy];
    
    if ( request != nil )
	{
        [self addRequest:request wihtKey:timestamp];
		[request startAsynchronous];
        return YES;
	}
    else
        NSLog(@"http request init fail - timestamp:%@", timestamp);
    
    return NO;
}

@end
