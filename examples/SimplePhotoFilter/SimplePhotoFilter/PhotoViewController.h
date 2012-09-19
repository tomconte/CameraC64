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
}

- (IBAction)updateSliderValue:(id)sender;
- (IBAction)takePhoto:(id)sender;

@end
