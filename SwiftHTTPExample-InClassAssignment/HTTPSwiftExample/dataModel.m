//
//  DataModel.m
//  MSL-Assignment-One
//
//  Created by UbiComp on 9/9/21.
//

#import "DataModel.h"

@implementation DataModel
@synthesize imageNames = _imageNames;


+(DataModel*)sharedInstance {
    static DataModel* _sharedInstance = nil;
    static dispatch_once_t predicate;
    
    dispatch_once(&predicate, ^{
        _sharedInstance = [[DataModel alloc] init];
    });
    return _sharedInstance;
}

//
//Array Getters
//



-(NSArray*)imageNames {
    if(!_imageNames) {
        [self loadNames];
    }
    return _imageNames;
}


-(int)loadNames {
    NSDictionary* fileDict = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"images" ofType:@"plist"]];
    
    
    _imageNames = [fileDict objectForKey:@"images"];
    
    return 1;
}

-(UIImage*)getImageWithName:(NSString*)name {
    UIImage* image = nil;
    
    
    image = [UIImage imageNamed:name];
    
    return image;
}

-(NSArray*)getAllImages {
    return _imageNames;
}


-(NSInteger)numberOfImages{ return self.imageNames.count; }




@end

