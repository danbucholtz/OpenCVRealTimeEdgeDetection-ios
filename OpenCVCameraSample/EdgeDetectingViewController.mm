//
//  EdgeDetectingViewController.m
//  OpenCVCameraSample
//
//  Created by Dan Bucholtz on 9/7/14.
//  Copyright (c) 2014 NXSW. All rights reserved.
//

#import "EdgeDetectingViewController.h"

#include <opencv2/imgproc/imgproc.hpp>
#include <opencv2/highgui/highgui.hpp>
#include <iostream>

#import "Rectangle.h"
#import "RectangleCALayer.h"

@implementation EdgeDetectingViewController

long frameNumber = 0;
NSMutableArray * queue;

NSObject * frameNumberLockObject = [[NSObject alloc] init];
NSObject * queueLockObject = [[NSObject alloc] init];
NSObject * aggregateRectangleLockObject = [[NSObject alloc] init];

Rectangle * aggregateRectangle;

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    frameNumber = 0;
    aggregateRectangle = nil;
    queue = [[NSMutableArray alloc] initWithCapacity:5];
}

- (void)processFrame:(cv::Mat&)mat videoRect:(CGRect)rect videoOrientation:(AVCaptureVideoOrientation)orientation{
    
    @synchronized(frameNumberLockObject){
        frameNumber++;
    }
    
    // Shrink video frame to 320X240
    cv::resize(mat, mat, cv::Size(), 0.25f, 0.25f, CV_INTER_LINEAR);
    rect.size.width /= 4.0f;
    rect.size.height /= 4.0f;
    
    // Rotate video frame by 90deg to portrait by combining a transpose and a flip
    // Note that AVCaptureVideoDataOutput connection does NOT support hardware-accelerated
    // rotation and mirroring via videoOrientation and setVideoMirrored properties so we
    // need to do the rotation in software here.
    cv::transpose(mat, mat);
    CGFloat temp = rect.size.width;
    rect.size.width = rect.size.height;
    rect.size.height = temp;
    
    if (orientation == AVCaptureVideoOrientationLandscapeRight)
    {
        // flip around y axis for back camera
        cv::flip(mat, mat, 1);
    }
    else {
        // Front camera output needs to be mirrored to match preview layer so no flip is required here
    }
    
    orientation = AVCaptureVideoOrientationPortrait;
    
    long start = [[NSDate date] timeIntervalSince1970 ] * 1000;
    
    Rectangle * rectangle = [self getLargestRectangleInFrame:mat];
    
    [self processRectangleFromFrame:rectangle inFrame:frameNumber];
    
    long end = [[NSDate date] timeIntervalSince1970 ] * 1000;
    
    long difference = end - start;
    NSLog([NSString stringWithFormat:@"Millis to calculate: %ld", difference]);
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self displayDataForVideoRect:rect videoOrientation:orientation];
    });
}

- (void) displayDataForVideoRect:(CGRect)rect videoOrientation:(AVCaptureVideoOrientation)videoOrientation{
    
    NSArray *sublayers = [NSArray arrayWithArray:[_videoPreviewLayer sublayers]];
    int sublayersCount = (int) [sublayers count];
    int currentSublayer = 0;
    
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    
    // hide all the drawing layers
    for (CALayer *layer in sublayers) {
        NSString *layerName = [layer name];
        if ([layerName isEqualToString:@"DrawingLayer"])
            [layer setHidden:YES];
    }
    
    CGAffineTransform t = [self affineTransformForVideoFrame:rect orientation:videoOrientation];
    
    if ( aggregateRectangle ){
        
        
        
        CGPoint transformedTopLeft = CGPointApplyAffineTransform(CGPointMake(aggregateRectangle.topLeftX, aggregateRectangle.topLeftY), t);
        CGPoint transformedTopRight = CGPointApplyAffineTransform(CGPointMake(aggregateRectangle.topRightX, aggregateRectangle.topRightY), t);
        CGPoint transformedBottomLeft = CGPointApplyAffineTransform(CGPointMake(aggregateRectangle.bottomLeftX, aggregateRectangle.bottomLeftY), t);
        CGPoint transformedBottomRight = CGPointApplyAffineTransform(CGPointMake(aggregateRectangle.bottomRightX, aggregateRectangle.bottomRightY), t);
        
        aggregateRectangle.topLeftX = transformedTopLeft.x;
        aggregateRectangle.topRightX = transformedTopRight.x;
        aggregateRectangle.bottomLeftX = transformedBottomLeft.x;
        aggregateRectangle.bottomRightX = transformedBottomRight.x;
        
        aggregateRectangle.topLeftY = transformedTopLeft.y;
        aggregateRectangle.topRightY = transformedTopRight.y;
        aggregateRectangle.bottomLeftY = transformedBottomLeft.y;
        aggregateRectangle.bottomRightY = transformedBottomRight.y;
    }
    
    CALayer *featureLayer = nil;
    
    // re-use an existing layer if possible
    while ( !featureLayer && (currentSublayer < sublayersCount) ) {
        CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
        if ( [[currentLayer name] isEqualToString:@"DrawingLayer"] ) {
            featureLayer = currentLayer;
            [currentLayer setHidden:NO];
        }
    }
    
    // create a new one if necessary
    if ( !featureLayer ) {
        featureLayer = [CALayer new];
        featureLayer.delegate = self;
        [featureLayer setName:@"DrawingLayer"];
        [_videoPreviewLayer addSublayer:featureLayer];
    }
    
    [featureLayer setFrame:_videoPreviewLayer.frame];
    [featureLayer setNeedsDisplay];
    
    [CATransaction commit];
}

- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)context {
    
    if ( aggregateRectangle ){
        CGContextSetStrokeColorWithColor(context, [[UIColor redColor] CGColor]);
        CGContextSetFillColorWithColor(context, [[UIColor redColor] CGColor]);
        
        CGContextMoveToPoint(context, aggregateRectangle.topLeftX, aggregateRectangle.topLeftY);
        
        CGContextAddLineToPoint(context, aggregateRectangle.topRightX, aggregateRectangle.topRightY);
        
        CGContextAddLineToPoint(context, aggregateRectangle.bottomRightX, aggregateRectangle.bottomRightY);
        
        CGContextAddLineToPoint(context, aggregateRectangle.bottomLeftX, aggregateRectangle.bottomLeftY);
        
        CGContextAddLineToPoint(context, aggregateRectangle.topLeftX, aggregateRectangle.topLeftY);
        
        CGContextDrawPath(context, kCGPathFillStroke);
    }
}







- (void) processRectangleFromFrame:(Rectangle *)rectangle inFrame:(long)frame{
    if ( !rectangle ){
        // the rectangle is null, so remove the oldest frame from the queue
        [self removeOldestFrameFromRectangleQueue];
        [self updateAggregateRectangle:rectangle];
    }
    else{
        BOOL significantChange = [self checkForSignificantChange:rectangle withAggregate:aggregateRectangle];
        if ( significantChange ){
            // empty the queue, and make the new rectangle the aggregated rectangle for now
            [self emptyQueue];
            [self updateAggregateRectangle:rectangle];
        }
        else{
            // remove the oldest frame
            [self removeOldestFrameFromRectangleQueue];
            // then add the new frame, and average the 5 to build an aggregate rectangle
            [self addRectangleToQueue:rectangle];
            Rectangle * aggregate = [self buildAggregateRectangleFromQueue];
            [self updateAggregateRectangle:aggregate];
        }
    }
}

- (Rectangle *) buildAggregateRectangleFromQueue{
    @synchronized(queueLockObject){
        double topLeftX = 0;
        double topLeftY = 0;
        double topRightX = 0;
        double topRightY = 0;
        double bottomLeftX = 0;
        double bottomLeftY = 0;
        double bottomRightX = 0;
        double bottomRightY = 0;
        
        if ( !queue ){
            return nil;
        }
        
        for ( int i = 0; i < [queue count]; i++ ){
            Rectangle * temp = [queue objectAtIndex:i];
            topLeftX = topLeftX + temp.topLeftX;
            topLeftY = topLeftY + temp.topLeftY;
            topRightX = topRightX + temp.topRightX;
            topRightY = topRightY + temp.topRightY;
            bottomLeftX = bottomLeftX + temp.bottomLeftX;
            bottomLeftY = bottomLeftY + temp.bottomLeftY;
            bottomRightX = bottomRightX + temp.bottomRightX;
            bottomRightY = bottomRightY + temp.bottomRightY;
        }
        
        Rectangle * aggregate = [[Rectangle alloc] init];
        aggregate.topLeftX = round(topLeftX/[queue count]);
        aggregate.topLeftY = round(topLeftY/[queue count]);
        aggregate.topRightX = round(topRightX/[queue count]);
        aggregate.topRightY = round(topRightY/[queue count]);
        aggregate.bottomLeftX = round(bottomLeftX/[queue count]);
        aggregate.bottomLeftY = round(bottomLeftY/[queue count]);
        aggregate.bottomRightX = round(bottomRightX/[queue count]);
        aggregate.bottomRightY = round(bottomRightY/[queue count]);
        
        return aggregate;
    }
}

- (void) updateAggregateRectangle:(Rectangle *)rectangle{
    @synchronized(aggregateRectangleLockObject){
        aggregateRectangle = rectangle;
    }
}

- (void) emptyQueue{
    @synchronized(queueLockObject){
        if ( queue ){
            [queue removeAllObjects];
        }
    }
}

- (BOOL) checkForSignificantChange:(Rectangle *)rectangle withAggregate:(Rectangle *)aggregate {
    @synchronized(aggregateRectangleLockObject){
        if ( !aggregate ){
            return YES;
        }
        else{
            // compare each point
            int maxDiff = 12;
            
            int topLeftXDiff = abs(rectangle.topLeftX - aggregate.topLeftX);
            int topLeftYDiff = abs(rectangle.topLeftY - aggregate.topLeftY);
            int topRightXDiff = abs(rectangle.topRightX - aggregate.topRightX);
            int topRightYDiff = abs(rectangle.topRightY - aggregate.topRightY);
            
            int bottomLeftXDiff = abs(rectangle.bottomLeftX - aggregate.bottomLeftX);
            int bottomLeftYDiff = abs(rectangle.bottomLeftY - aggregate.bottomLeftY);
            int bottomRightXDiff = abs(rectangle.bottomRightX - aggregate.bottomRightX);
            int bottomRightYDiff = abs(rectangle.bottomRightY - aggregate.bottomRightY);
            
            if ( topLeftXDiff > maxDiff || topLeftYDiff > maxDiff || topRightXDiff > maxDiff || topRightYDiff > maxDiff || bottomLeftXDiff > maxDiff || bottomLeftYDiff > maxDiff || bottomRightXDiff > maxDiff || bottomRightYDiff > maxDiff ){
                
                return YES;
            }
            
            return NO;
        }
    }
}

- (void) removeOldestFrameFromRectangleQueue{
    @synchronized(queueLockObject){
        if ( queue ){
            int index = (int)[queue count] - 1;
            if ( index >= 0 ){
                [queue removeObjectAtIndex:index];
            }
        }
    }
}

- (void) addRectangleToQueue:(Rectangle *)rectangle{
    @synchronized(queueLockObject){
        if ( queue ){
            // per apple docs, If index is already occupied, the objects at index and beyond are shifted by adding 1 to their indices to make room.
            // put the rectangle at index 0 and let the NSArray scoot everything back one position
            [queue insertObject:rectangle atIndex:0];
        }
    }
}

- (Rectangle *) getLargestRectangleInFrame:(cv::Mat)mat{
    return nil;
}

@end