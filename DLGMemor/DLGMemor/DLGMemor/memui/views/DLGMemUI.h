//
//  DLGMemUI.h
//  memui
//
//  Created by DeviLeo on 2017/1/14.
//  Copyright © 2017 Liu Junqi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "category/UIWindow+DLGMemUI.h"
#import "DLGMemUIViewDelegate.h"

@interface DLGMemUI : NSObject

+ (void)addDLGMemUIView:(id<DLGMemUIViewDelegate>)delegate;
+ (void)addDLGMemUIViewToWindow:(UIWindow *)window withDelegate:(id<DLGMemUIViewDelegate>)delegate;
+ (void)removeDLGMemUIView;

@end
