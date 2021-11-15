//
//  dataModel.h
//  HTTPSwiftExample
//
//  Created by William Chan on 11/14/21.
//  Copyright © 2021 Eric Larson. All rights reserved.
//



#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DataModel : NSObject

+(DataModel*)sharedInstance;

-(int)loadNames;

-(UIImage*)getImageWithName:(NSString*)name;

-(NSArray*)getAllImages;

-(NSInteger)numberOfImages;



@property (nonatomic, strong) NSArray* imageNames;

@end

NS_ASSUME_NONNULL_END



