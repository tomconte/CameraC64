#import "GPUImageFastC64Filter.h"
#import "GPUImagePicture.h"
#import "GPUImageLookupFilter.h"

@implementation GPUImageFastC64Filter

- (id)initWithCLUT:(NSString *)clutFile;
{
    if (!(self = [super init]))
    {
		return nil;
    }

    UIImage *image = [UIImage imageNamed:clutFile];
    
    lookupImageSource = [[GPUImagePicture alloc] initWithImage:image];
    GPUImageLookupFilter *lookupFilter = [[GPUImageLookupFilter alloc] init];

    [lookupImageSource addTarget:lookupFilter atTextureLocation:1];
    [lookupImageSource processImage];

    self.initialFilters = [NSArray arrayWithObjects:lookupFilter, nil];
    self.terminalFilter = lookupFilter;
    
    return self;
}

#pragma mark -
#pragma mark Accessors

@end
