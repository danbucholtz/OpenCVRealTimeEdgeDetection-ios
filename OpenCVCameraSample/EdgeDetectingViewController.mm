//
//  EdgeDetectingViewController.m
//  OpenCVVideoFeedSample
//
//  Created by Dan Bucholtz on 9/2/14.
//  Copyright (c) 2014 NXSW. All rights reserved.
//

#import "EdgeDetectingViewController.h"

#include <opencv2/imgproc/imgproc.hpp>
#include <opencv2/highgui/highgui.hpp>
#include <iostream>

#import "Rectangle.h"
#import "RectangleCALayer.h"

@implementation EdgeDetectingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)processFrame:(cv::Mat&)mat videoRect:(CGRect)rect videoOrientation:(AVCaptureVideoOrientation)orientation{
    
    // Shrink video frame to 320X240
    cv::resize(mat, mat, cv::Size(), 0.5f, 0.5f, CV_INTER_LINEAR);
    rect.size.width /= 2.0f;
    rect.size.height /= 2.0f;
    
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
    
    Rectangle * rectangle = [self getLargestRectangleInFrame:mat];
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self displayData:rectangle
             forVideoRect:rect
         videoOrientation:orientation];
    });
}

- (void) displayData:(Rectangle *)rectangle forVideoRect:(CGRect)rect videoOrientation:(AVCaptureVideoOrientation)videoOrientation{
    
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
    
    CGPoint transformedTopLeft = CGPointApplyAffineTransform(CGPointMake(rectangle.topLeftX, rectangle.topLeftY), t);
    CGPoint transformedTopRight = CGPointApplyAffineTransform(CGPointMake(rectangle.topRightX, rectangle.topRightY), t);
    CGPoint transformedBottomLeft = CGPointApplyAffineTransform(CGPointMake(rectangle.bottomLeftX, rectangle.bottomLeftY), t);
    CGPoint transformedBottomRight = CGPointApplyAffineTransform(CGPointMake(rectangle.bottomRightX, rectangle.bottomRightY), t);
    
    rectangle.topLeftX = transformedTopLeft.x;
    rectangle.topRightX = transformedTopRight.x;
    rectangle.bottomLeftX = transformedBottomLeft.x;
    rectangle.bottomRightX = transformedBottomRight.x;
    
    rectangle.topLeftY = transformedTopLeft.y;
    rectangle.topRightY = transformedTopRight.y;
    rectangle.bottomLeftY = transformedBottomLeft.y;
    rectangle.bottomRightY = transformedBottomRight.y;
    
    CALayer *featureLayer = nil;
    
    // re-use an existing layer if possible
    while ( !featureLayer && (currentSublayer < sublayersCount) ) {
        CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
        if ( [[currentLayer name] isEqualToString:@"DrawingLayer"] ) {
            featureLayer = currentLayer;
            ((RectangleCALayer *)featureLayer).rectangle = rectangle;
            [currentLayer setHidden:NO];
        }
    }
    
    // create a new one if necessary
    if ( !featureLayer ) {
        featureLayer = [RectangleCALayer new];
        featureLayer.delegate = self;
        ((RectangleCALayer *)featureLayer).rectangle = rectangle;
        [featureLayer setName:@"DrawingLayer"];
        [_videoPreviewLayer addSublayer:featureLayer];
    }
    
    [featureLayer setFrame:_videoPreviewLayer.frame];
    [featureLayer setNeedsDisplay];
    
    [CATransaction commit];
}

- (Rectangle *) getLargestRectangleInFrame:(cv::Mat)mat{
    long start = [[NSDate date] timeIntervalSince1970 ] * 1000;
    cv::vector<cv::vector<cv::Point>>squares;
    cv::vector<cv::Point> largest_square;
    
    find_squares(mat, squares);
    find_largest_square(squares, largest_square);
    Rectangle * rectangle;
    if (largest_square.size() == 4 ){
        NSMutableArray * points = [[NSMutableArray alloc] initWithCapacity:4];
        [points addObject:[NSValue valueWithCGPoint:CGPointMake(largest_square[0].x, largest_square[0].y)]];
        [points addObject:[NSValue valueWithCGPoint:CGPointMake(largest_square[1].x, largest_square[1].y)]];
        [points addObject:[NSValue valueWithCGPoint:CGPointMake(largest_square[2].x, largest_square[2].y)]];
        [points addObject:[NSValue valueWithCGPoint:CGPointMake(largest_square[3].x, largest_square[3].y)]];
        
        // okay, sort it by the X, then split it
        NSArray * sortedArray = [points sortedArrayUsingComparator:^NSComparisonResult(NSValue *obj1, NSValue *obj2) {
            CGPoint firstPoint = [obj1 CGPointValue];
            CGPoint secondPoint = [obj2 CGPointValue];
            if (firstPoint.x > secondPoint.x) {
                return NSOrderedDescending;
            } else if (firstPoint.x < secondPoint.x) {
                return NSOrderedAscending;
            } else {
                return NSOrderedSame;
            }
        }];
        
        // we're sorted on X, so grab two of those bitches and figure out top and bottom
        NSMutableArray * left = [[NSMutableArray alloc] initWithCapacity:2];
        NSMutableArray * right = [[NSMutableArray alloc] initWithCapacity:2];
        [left addObject:sortedArray[0]];
        [left addObject:sortedArray[1]];
        
        [right addObject:sortedArray[2]];
        [right addObject:sortedArray[3]];
        
        // okay, now sort each of those arrays on the Y access
        NSArray * sortedLeft = [left sortedArrayUsingComparator:^NSComparisonResult(NSValue *obj1, NSValue *obj2) {
            CGPoint firstPoint = [obj1 CGPointValue];
            CGPoint secondPoint = [obj2 CGPointValue];
            if (firstPoint.y > secondPoint.y) {
                return NSOrderedDescending;
            } else if (firstPoint.y < secondPoint.y) {
                return NSOrderedAscending;
            } else {
                return NSOrderedSame;
            }
        }];
        
        NSArray * sortedRight = [right sortedArrayUsingComparator:^NSComparisonResult(NSValue *obj1, NSValue *obj2) {
            CGPoint firstPoint = [obj1 CGPointValue];
            CGPoint secondPoint = [obj2 CGPointValue];
            if (firstPoint.y > secondPoint.y) {
                return NSOrderedDescending;
            } else if (firstPoint.y < secondPoint.y) {
                return NSOrderedAscending;
            } else {
                return NSOrderedSame;
            }
        }];
        
        CGPoint topLeftOriginal = [[sortedLeft objectAtIndex:0] CGPointValue];
        
        CGPoint topRightOriginal = [[sortedRight objectAtIndex:0] CGPointValue];
        
        CGPoint bottomLeftOriginal = [[sortedLeft objectAtIndex:1] CGPointValue];
        
        CGPoint bottomRightOriginal = [[sortedRight objectAtIndex:1] CGPointValue];
        
        rectangle = [[Rectangle alloc] init];
        
        
        rectangle.bottomLeftX = bottomLeftOriginal.x;
        rectangle.bottomRightX = bottomRightOriginal.x;
        rectangle.topLeftX = topLeftOriginal.x;
        rectangle.topRightX = topRightOriginal.x;
        
        rectangle.bottomLeftY = bottomLeftOriginal.y;
        rectangle.bottomRightY = bottomRightOriginal.y;
        rectangle.topLeftY = topLeftOriginal.y;
        rectangle.topRightY = topRightOriginal.y;
    }
    long end = [[NSDate date] timeIntervalSince1970 ] * 1000;
    
    long difference = end - start;
    NSLog([NSString stringWithFormat:@"Millis to calculate: %ld", difference]);
    
    return rectangle;
}

- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)context {
    
    if ( [layer isKindOfClass:[RectangleCALayer class]] ){
        
        Rectangle * toDraw = ((RectangleCALayer *)layer).rectangle;
        if ( toDraw ){
            CGContextSetStrokeColorWithColor(context, [[UIColor redColor] CGColor]);
            CGContextSetFillColorWithColor(context, [[UIColor redColor] CGColor]);
            
            CGContextMoveToPoint(context, toDraw.topLeftX, toDraw.topLeftY);
            
            CGContextAddLineToPoint(context, toDraw.topRightX, toDraw.topRightY);
            
            CGContextAddLineToPoint(context, toDraw.bottomRightX, toDraw.bottomRightY);
            
            CGContextAddLineToPoint(context, toDraw.bottomLeftX, toDraw.bottomLeftY);
            
            CGContextAddLineToPoint(context, toDraw.topLeftX, toDraw.topLeftY);
            
            CGContextDrawPath(context, kCGPathFillStroke);
        }
    }
}


void find_squares(cv::Mat& image, cv::vector<cv::vector<cv::Point>>&squares) {
    
    // blur will enhance edge detection
    cv::Mat blurred(image);
    medianBlur(image, blurred, 7);
    
    cv::Mat gray0(blurred.size(), CV_8U), gray;
    cv::vector<cv::vector<cv::Point>> contours;
    
    // find squares in every color plane of the image
    for (int c = 0; c < 3; c++)
    {
        int ch[] = {c, 0};
        mixChannels(&blurred, 1, &gray0, 1, ch, 1);
        
        // try several threshold levels
        const int threshold_level = 2;
        for (int l = 0; l < threshold_level; l++)
        {
            // Use Canny instead of zero threshold level!
            // Canny helps to catch squares with gradient shading
            if (l == 0){
                Canny(gray0, gray, 10, 20, 3); //
                
                // Dilate helps to remove potential holes between edge segments
                dilate(gray, gray, cv::Mat(), cv::Point(-1,-1));
            }
            else{
                gray = gray0 >= (l+1) * 255 / threshold_level;
                //cv::Size size = image.size();
                //cv::adaptiveThreshold(gray0, gray, threshold_level, CV_ADAPTIVE_THRESH_GAUSSIAN_C, CV_THRESH_BINARY, (size.width + size.height) / 200, l);
            }
            
            // Find contours and store them in a list
            findContours(gray, contours, CV_RETR_LIST, CV_CHAIN_APPROX_SIMPLE);
            
            // Test contours
            cv::vector<cv::Point> approx;
            for (size_t i = 0; i < contours.size(); i++)
            {
                // approximate contour with accuracy proportional
                // to the contour perimeter
                approxPolyDP(cv::Mat(contours[i]), approx, arcLength(cv::Mat(contours[i]), true)*0.02, true);
                
                // Note: absolute value of an area is used because
                // area may be positive or negative - in accordance with the
                // contour orientation
                //if (approx.size() == 4 && fabs(contourArea(cv::Mat(approx))) > 100 && isContourConvex(cv::Mat(approx)))
                if (approx.size() == 4 && fabs(contourArea(cv::Mat(approx))) > 500 ){
                    //if ( approx.size() == 4 ){
                    double maxCosine = 0;
                    
                    for (int j = 2; j < 5; j++){
                        double cosine = fabs(angle(approx[j%4], approx[j-2], approx[j-1]));
                        maxCosine = MAX(maxCosine, cosine);
                    }
                    
                    if (maxCosine < 0.3)
                        squares.push_back(approx);
                }
            }
        }
    }
}

double angle( cv::Point pt1, cv::Point pt2, cv::Point pt0 ) {
    double dx1 = pt1.x - pt0.x;
    double dy1 = pt1.y - pt0.y;
    double dx2 = pt2.x - pt0.x;
    double dy2 = pt2.y - pt0.y;
    return (dx1*dx2 + dy1*dy2)/sqrt((dx1*dx1 + dy1*dy1)*(dx2*dx2 + dy2*dy2) + 1e-10);
}

void find_largest_square(const cv::vector<cv::vector<cv::Point> >& squares, cv::vector<cv::Point>& biggest_square)
{
    if (!squares.size()){
        // no squares detected
        return;
    }
    
    /*int max_width = 0;
     int max_height = 0;
     int max_square_idx = 0;
     
     for (size_t i = 0; i < squares.size(); i++)
     {
     // Convert a set of 4 unordered Points into a meaningful cv::Rect structure.
     cv::Rect rectangle = boundingRect(cv::Mat(squares[i]));
     
     //        cout << "find_largest_square: #" << i << " rectangle x:" << rectangle.x << " y:" << rectangle.y << " " << rectangle.width << "x" << rectangle.height << endl;
     
     // Store the index position of the biggest square found
     if ((rectangle.width >= max_width) && (rectangle.height >= max_height))
     {
     max_width = rectangle.width;
     max_height = rectangle.height;
     max_square_idx = (int) i;
     }
     }
     
     biggest_square = squares[max_square_idx];
     */
    
    double maxArea = 0;
    int largestIndex = -1;
    
    for ( int i = 0; i < squares.size(); i++){
        cv::vector<cv::Point> square = squares[i];
        double area = contourArea(cv::Mat(square));
        if ( area >= maxArea){
            largestIndex = i;
            maxArea = area;
        }
    }
    if ( largestIndex >= 0 && largestIndex < squares.size() ){
        biggest_square = squares[largestIndex];
    }
    return;
}

@end