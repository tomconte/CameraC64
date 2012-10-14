#import "GPUImageC64Filter.h"
#import "GPUImagePicture.h"
#import "GPUImage8BitLookupFilter.h"

@implementation GPUImageC64Filter

- (id)initWithCLUT1:(NSString *)clut1File andCLUT2:(NSString *)clut2File;
{
    if (!(self = [super init]))
    {
		return nil;
    }

    UIImage *image = [UIImage imageNamed:clut1File];
    UIImage *image2 = [UIImage imageNamed:clut2File];
    
    lookupImageSource = [[GPUImagePicture alloc] initWithImage:image];
    lookupImageSource2 = [[GPUImagePicture alloc] initWithImage:image2];
    GPUImage8BitLookupFilter *lookupFilter = [[GPUImage8BitLookupFilter alloc] init];

    [lookupImageSource addTarget:lookupFilter atTextureLocation:1];
    [lookupImageSource processImage];

    [lookupImageSource2 addTarget:lookupFilter atTextureLocation:2];
    [lookupImageSource2 processImage];

    self.initialFilters = [NSArray arrayWithObjects:lookupFilter, nil];
    self.terminalFilter = lookupFilter;
    
    return self;
}

#pragma mark -
#pragma mark Accessors

@end
