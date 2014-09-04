//
//  RectangleCALayer.h
//  DocBox
//
//  Created by Dan Bucholtz on 8/26/14.
//  Copyright (c) 2014 Mod618. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

@class Rectangle;

@interface RectangleCALayer : CALayer{
    Rectangle * rectangle;
}

@property (nonatomic, strong) Rectangle * rectangle;

@end