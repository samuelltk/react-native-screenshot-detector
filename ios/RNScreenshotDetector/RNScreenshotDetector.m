//
//  RNScreenshotDetector.m
//
//  Created by Graham Carling on 1/11/17.
//

#import "RNScreenshotDetector.h"
#import "RCTBridge.h"
#import "RCTEventDispatcher.h"

#import <Photos/Photos.h>
#import <UIKit/UIKit.h>
#import "RCTLog.h"

@implementation RNScreenshotDetector

NSMapTable *_successCallbacks;

RCT_EXPORT_MODULE();

- (NSArray<NSString *> *)supportedEvents {
    return @[@"ScreenshotWillTaken",@"ScreenshotTaken"];
}

- (void)setupAndListen:(RCTBridge*)bridge {
    // First set up native bridge
    [self setBridge:bridge];
    // Now set up handler to detect if user takes a screenshot
    NSOperationQueue *mainQueue = [NSOperationQueue mainQueue];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationUserDidTakeScreenshotNotification
                                                      object:nil
                                                       queue:mainQueue
                                                  usingBlock:^(NSNotification *notification) {
                                                      [self.bridge.eventDispatcher sendAppEventWithName:@"ScreenshotWillTaken" body:notification];
                                                      
                                                      double delayInSeconds = 1.0;
                                                      __block RCTEventEmitter* bself = self;
                                                      dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
                                                      dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                                                         [self screenshotDetected:notification];
                                                      });
                                                  }];
}

- (void)screenshotDetected:(NSNotification *)notification {
    NSLog(@"%@",notification);
    [self.bridge.eventDispatcher sendAppEventWithName:@"ScreenshotTaken" body:notification];
}

RCT_EXPORT_METHOD(saveImage:(NSDictionary *)obj successCallback:(RCTResponseSenderBlock)successCallback errorCallback:(RCTResponseErrorBlock)errorCallback)
{
    if (!_successCallbacks) {
        _successCallbacks = [NSMapTable strongToStrongObjectsMapTable];
    }
    
    NSString *imagePath = obj[@"imagePath"];
    NSString *imageName = obj[@"imageName"];
    NSString *imageType = obj[@"imageType"];
    int width =  [obj[@"width"] intValue];
    int height =  [obj[@"height"] intValue];
    
    // Create NSURL from uri
    NSURL *url = [[NSURL alloc] initWithString:imagePath];
    
    PHFetchResult *result = [PHAsset fetchAssetsWithALAssetURLs:@[url] options:nil];
    PHAsset *asset = result.firstObject;
    
    if (asset) {
        PHCachingImageManager *imageManager = [[PHCachingImageManager alloc] init];
        
        PHImageRequestOptions *option = [PHImageRequestOptions new];
        option.synchronous = YES;
        
        [_successCallbacks setObject:successCallback forKey:imageManager];
        // Request an image for the asset from the PHCachingImageManager.
        [imageManager requestImageForAsset:asset targetSize:CGSizeMake(width, height) contentMode:PHImageContentModeAspectFit options:option
                             resultHandler:^(UIImage *image, NSDictionary *info)
         {
             NSArray * paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
             NSString * basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
             
             NSData * binaryImageData;
             if([imageType isEqualToString:@"png"]) {
                 binaryImageData = UIImagePNGRepresentation(image);
             } else {
                 binaryImageData = UIImageJPEGRepresentation(image, 1.0);
             }
             NSString *imageNameWithExtension = [NSString stringWithFormat:@"%@.%@", imageName, imageType];
             [binaryImageData writeToFile:[basePath stringByAppendingPathComponent:imageNameWithExtension] atomically:YES];
             
             // Call the callback
             RCTResponseSenderBlock successCallback = [_successCallbacks objectForKey:imageManager];
             if (successCallback) {
                 successCallback(@[@"Success"]);
                 [_successCallbacks removeObjectForKey:imageManager];
             } else {
                 RCTLogWarn(@"No callback registered for success");
             }
         }
         ];
    } else {
        // Check if the photo is in the photo stream
        NSString *localIDFragment = [[[[imagePath componentsSeparatedByString: @"="] objectAtIndex: 1] componentsSeparatedByString: @"&"] objectAtIndex: 0];
        PHFetchResult *fetchResultForPhotostream = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAlbumMyPhotoStream options: nil];
        
        if (fetchResultForPhotostream.count > 0) {
            PHAssetCollection *photostream = fetchResultForPhotostream [0];
            
            PHFetchOptions *optionsForFetch = [[PHFetchOptions alloc] init];;
            optionsForFetch.includeHiddenAssets = YES;
            PHFetchResult *fetchResultForPhotostreamAssets = [PHAsset fetchAssetsInAssetCollection:photostream options:optionsForFetch];
            
            if (fetchResultForPhotostreamAssets.count > 0) {
                NSIndexSet *i = [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(0, fetchResultForPhotostreamAssets.count)];
                //let i=NSIndexSet(indexesInRange: NSRange(location: 0,length: fetchResultForPhotostreamAssets.count))
                
                [_successCallbacks setObject:successCallback forKey:photostream];
                [fetchResultForPhotostreamAssets enumerateObjectsAtIndexes: i options: NSEnumerationReverse usingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    PHAsset *target = obj;
                    NSString *identifier = target.localIdentifier;
                    if ([identifier rangeOfString: localIDFragment].length != 0) {
                        if (target) {
                            // get photo info from this asset
                            PHImageRequestOptions * imageRequestOptions = [[PHImageRequestOptions alloc] init];
                            imageRequestOptions.synchronous = YES;
                            [[PHImageManager defaultManager]
                             requestImageDataForAsset:target
                             options:imageRequestOptions
                             resultHandler:^(NSData *imageData, NSString *dataUTI,
                                             UIImageOrientation orientation,
                                             NSDictionary *info)
                             {
                                 if ([info objectForKey:@"PHImageFileURLKey"]) {
                                     
                                     NSArray * paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                                     NSString * basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
                                     
                                     NSString *imageNameWithExtension = [NSString stringWithFormat:@"%@.%@", imageName, imageType];
                                     [imageData writeToFile:[basePath stringByAppendingPathComponent:imageNameWithExtension] atomically:YES];
                                     // Call the callback
                                     RCTResponseSenderBlock successCallback = [_successCallbacks objectForKey:photostream];
                                     if (successCallback) {
                                         successCallback(@[@"Success"]);
                                         [_successCallbacks removeObjectForKey:photostream];
                                     } else {
                                         RCTLogWarn(@"No callback registered for success");
                                     }
                                 }
                             }];
                        }
                    }
                }];
            }
        }
    }
}

@end
