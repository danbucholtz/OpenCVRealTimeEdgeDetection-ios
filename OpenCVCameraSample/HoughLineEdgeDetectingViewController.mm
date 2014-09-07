//
//  HoughLineEdgeDetectingViewController.m
//  OpenCVCameraSample
//
//  Created by Dan Bucholtz on 9/6/14.
//  Copyright (c) 2014 NXSW. All rights reserved.
//

#import "HoughLineEdgeDetectingViewController.h"

#include <opencv2/imgproc/imgproc.hpp>
#include <opencv2/highgui/highgui.hpp>
#include <iostream>

#import "Rectangle.h"
#import "RectangleCALayer.h"

@implementation HoughLineEdgeDetectingViewController

- (Rectangle *) getLargestRectangleInFrame:(cv::Mat)mat{
    long start = [[NSDate date] timeIntervalSince1970 ] * 1000;
    
    Rectangle * rectangle = findHoughLines(mat);
    
    long end = [[NSDate date] timeIntervalSince1970 ] * 1000;
    
    long difference = end - start;
    NSLog([NSString stringWithFormat:@"Millis to calculate: %ld", difference]);
    
    return rectangle;
}

cv::Point2f computeIntersect(cv::Vec4i a,
                             cv::Vec4i b)
{
	int x1 = a[0], y1 = a[1], x2 = a[2], y2 = a[3], x3 = b[0], y3 = b[1], x4 = b[2], y4 = b[3];
    
	if (float d = ((float)(x1 - x2) * (y3 - y4)) - ((y1 - y2) * (x3 - x4)))
	{
		cv::Point2f pt;
		pt.x = ((x1 * y2 - y1 * x2) * (x3 - x4) - (x1 - x2) * (x3 * y4 - y3 * x4)) / d;
		pt.y = ((x1 * y2 - y1 * x2) * (y3 - y4) - (y1 - y2) * (x3 * y4 - y3 * x4)) / d;
		return pt;
	}
	else
		return cv::Point2f(-1, -1);
}

void sortCorners(std::vector<cv::Point2f>& corners, cv::Point2f center)
{
	std::vector<cv::Point2f> top, bot;
    
	for (int i = 0; i < corners.size(); i++)
	{
		if (corners[i].y < center.y)
			top.push_back(corners[i]);
		else
			bot.push_back(corners[i]);
	}
    
	cv::Point2f tl = top[0].x > top[1].x ? top[1] : top[0];
	cv::Point2f tr = top[0].x > top[1].x ? top[0] : top[1];
	cv::Point2f bl = bot[0].x > bot[1].x ? bot[1] : bot[0];
	cv::Point2f br = bot[0].x > bot[1].x ? bot[0] : bot[1];
    
	corners.clear();
	corners.push_back(tl);
	corners.push_back(tr);
	corners.push_back(br);
	corners.push_back(bl);
}

Rectangle* findHoughLines (cv::Mat image){
    cv::Mat bw;
	cv::cvtColor(image, bw, CV_BGR2GRAY);
	cv::blur(bw, bw, cv::Size(3, 3));
	cv::Canny(bw, bw, 100, 100, 3);
    std::vector<cv::Vec4i> lines;
	cv::HoughLinesP(bw, lines, 1, CV_PI/180, 70, 30, 10);
    
    // Expand the lines
	for (int i = 0; i < lines.size(); i++){
		cv::Vec4i v = lines[i];
		lines[i][0] = 0;
		lines[i][1] = ((float)v[1] - v[3]) / (v[0] - v[2]) * -v[0] + v[1];
		lines[i][2] = image.cols;
		lines[i][3] = ((float)v[1] - v[3]) / (v[0] - v[2]) * (image.cols - v[2]) + v[3];
	}
    
    std::vector<cv::Point2f> corners;
	for (int i = 0; i < lines.size(); i++){
		for (int j = i+1; j < lines.size(); j++){
			cv::Point2f pt = computeIntersect(lines[i], lines[j]);
			if (pt.x >= 0 && pt.y >= 0){
				corners.push_back(pt);
            }
		}
	}
    
    std::vector<cv::Point2f> approx;
	cv::approxPolyDP(cv::Mat(corners), approx, cv::arcLength(cv::Mat(corners), true) * 0.02, true);
    
    if (approx.size() == 4){
        
        cv::Point2f center(0,0);
        for (int i = 0; i < corners.size(); i++){
            center += corners[i];
        }
        center *= (1. / corners.size());
        
        sortCorners(corners, center);
        
        Rectangle * rectangle = [[Rectangle alloc] init];
        rectangle.topLeftX = corners[0].x;
        rectangle.topLeftY = corners[0].y;
        rectangle.topRightX = corners[1].x;
        rectangle.topRightY = corners[1].y;
        rectangle.bottomRightX = corners[2].x;
        rectangle.bottomRightY = corners[2].y;
        rectangle.bottomLeftX = corners[3].x;
        rectangle.bottomLeftY = corners[3].y;
    }
    return nil;
}

@end