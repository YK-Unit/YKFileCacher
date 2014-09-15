//
//  YKFileCacher.h
//  YKFileCacherDemo
//
//  Created by zhang zhiyu on 13-7-6.
//  Copyright (c) 2013年 York. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ASIHTTPRequest.h"

extern NSString *const yk_networkDisconnectNotification;
extern NSString *const yk_fileCacheDownloadFinishedNotification;

@interface YKFileCacher : NSObject
<ASIHTTPRequestDelegate>
{
    /**
     *	@brief	The request time out.
     */
    NSInteger requestTimeout;
    
    /**
     *	@brief	The filecache directory.
     */
    NSString *cacheDirectory;
    
@protected
    /**
     *	@brief	Maintain the requests those are in processing.
     */
    NSMutableDictionary *processingRequests;

    /**
     * @brief   the queue of parsering responsedata task
     */
    dispatch_queue_t parserQueue;
    
}

@property (nonatomic,assign) NSInteger requestTimeout;
@property (nonatomic,copy) NSString *cacheDirectory;
@property (nonatomic,retain) NSMutableDictionary *processingRequests;


/**
 *	@brief	Shared instance.
 *
 *	@return	The global Client manager instance.
 */
+ (YKFileCacher *)sharedCacher;

/**
 *	@brief	clear all caches in current cache directory
 *
 *	@return	the flag to tell whether clear successfully
 */
- (BOOL)clearAllCaches;

/**
 *	@brief	clear all caches in current cache directory
 *
 *	@return	the flag to tell whether the file exit in cache directory
 */
- (BOOL)hasCachedFile:(NSString *)fileUrlStr;

/**
 *	@brief	get the path of file in current cache directory
 *
 *	@return	if,the file had cached in current cache directory,
 *          return the path of file;
 *          if not,
 *          return nil.
 */
- (NSString *)pathInCurrentCacheDirectory:(NSString *)fileUrlStr;

/**
 *	@brief	add a task to download a file
 *
 *  @return	the flag to tell whether add task successfully
 */
- (BOOL)addFileCacheTask:(NSString *)fileUrlStr;

- (BOOL)addImageCacheTask:(NSString *)imageUrlStr forView:(UIView *)view;
@end
