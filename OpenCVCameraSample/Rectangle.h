//
//  Rectangle.h
//  DocBox
//
//  Created by Dan Bucholtz on 4/19/14.
//  Copyright (c) 2014 Mod618. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Rectangle : NSObject{
    int topLeftX;
    int topLeftY;
    int topRightX;
    int topRightY;
    int bottomLeftX;
    int bottomLeftY;
    int bottomRightX;
    int bottomRightY;
}

@property(nonatomic, assign) int topLeftX;
@property(nonatomic, assign) int topLeftY;
@property(nonatomic, assign) int topRightX;
@property(nonatomic, assign) int topRightY;
@property(nonatomic, assign) int bottomLeftX;
@property(nonatomic, assign) int bottomLeftY;
@property(nonatomic, assign) int bottomRightX;
@property(nonatomic, assign) int bottomRightY;

@end