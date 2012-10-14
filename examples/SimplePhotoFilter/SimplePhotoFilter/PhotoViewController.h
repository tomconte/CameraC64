#import <UIKit/UIKit.h>
#import "GPUImage.h"

@interface PhotoViewController : UIViewController <UIAlertViewDelegate>
{
    GPUImageStillCamera *stillCamera;
    GPUImageOutput<GPUImageInput> *filter;
    UISlider *filterSettingsSlider;
    UIButton *photoCaptureButton;
    UILabel *msgLabel;
    GPUImageView *imageView;
    NSData *resultJPEG;
    UIImageView *capturedImage;
    
    UIButton *discardButton;
    UIButton *saveButton;
    UIButton *changeFilterButton;
    UIButton *titleBar;
    UIButton *powerBar;
    UIButton *flashButton;
    UIButton *scanlineButton;

    UIImageView *imageScanlineView;
    UIImageView *imageScreen;

    int curFilter;
    bool iPhone5;
    bool scanlineOn;
    bool isScreenOff;
    NSArray *_products;
}

- (IBAction)takePhoto:(id)sender;

@end
