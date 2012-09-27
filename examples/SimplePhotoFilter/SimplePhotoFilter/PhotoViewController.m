#import "PhotoViewController.h"
#import "UIDeviceHardware.h"
#import <AssetsLibrary/AssetsLibrary.h>

@interface PhotoViewController ()

@end

@implementation PhotoViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)loadView 
{
	CGRect mainScreenFrame = [[UIScreen mainScreen] bounds];
	    
    // Yes, I know I'm a caveman for doing all this by hand
	UIView *primaryView = [[UIView alloc] initWithFrame:mainScreenFrame];
	primaryView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    if (mainScreenFrame.size.height == 1136/2) {
        imageView = [[GPUImageView alloc] initWithFrame:CGRectMake(0, 20, 640/2, 852/2)];
    } else {
        imageView = [[GPUImageView alloc] initWithFrame:CGRectMake(0, 0, 640/2, 852/2)];
    }
    [primaryView addSubview:imageView];

    UIImageView *titleBar = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"newtitlebar.png"]];
    [titleBar setFrame:CGRectMake(0, 0, mainScreenFrame.size.width, 20)];
    [primaryView addSubview:titleBar];

    UIImage *btnImageUp = [UIImage imageNamed:@"buttonUp.png"];
    UIImage *btnImageDown = [UIImage imageNamed:@"buttonDown.png"];
    
    photoCaptureButton = [UIButton buttonWithType:UIButtonTypeCustom];
//    photoCaptureButton.backgroundColor = [UIColor brownColor];
//    photoCaptureButton.frame = CGRectMake(round(mainScreenFrame.size.width / 2.0 - 150.0 / 2.0), mainScreenFrame.size.height - 54.0, 150.0, 54.0);
    photoCaptureButton.frame = CGRectMake(0, mainScreenFrame.size.height - 54.0, mainScreenFrame.size.width, 54.0);
    [photoCaptureButton setImage:btnImageUp forState:UIControlStateNormal];
    [photoCaptureButton setImage:btnImageDown forState:UIControlStateHighlighted];
    photoCaptureButton.adjustsImageWhenDisabled = NO;
//    [photoCaptureButton setTitle:@"Capture Photo" forState:UIControlStateNormal];
	photoCaptureButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [photoCaptureButton addTarget:self action:@selector(takePhoto:) forControlEvents:UIControlEventTouchUpInside];
//    [photoCaptureButton setTitleColor:[UIColor grayColor] forState:UIControlStateDisabled];
//    [photoCaptureButton setAlpha:0.5];
    
    [primaryView addSubview:photoCaptureButton];
        
	self.view = primaryView;	
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    GLint maxTextureSize = [GPUImageOpenGLESContext maximumTextureSizeForThisDevice];
    bool isFast = (maxTextureSize > 2048);
    
//    stillCamera = [[GPUImageStillCamera alloc] init];
    stillCamera = [[GPUImageStillCamera alloc] initWithSessionPreset:AVCaptureSessionPreset640x480 cameraPosition:AVCaptureDevicePositionBack];
    stillCamera.outputImageOrientation = UIInterfaceOrientationPortrait;
//    filter = [[GPUImageGammaFilter alloc] init];
//    filter = [[GPUImageSketchFilter alloc] init];
//    [(GPUImageSketchFilter *)filter setTexelHeight:(1.0 / 1024.0)];
//    [(GPUImageSketchFilter *)filter setTexelWidth:(1.0 / 768.0)];
//    filter = [[GPUImageSmoothToonFilter alloc] init];
//    filter = [[GPUImageSepiaFilter alloc] init];

//    filter = [[GPUImageC64ColorspaceFilter alloc] init];
    
    filter = [[GPUImageFilterGroup alloc] init];
    
    GPUImageTransformFilter *transformFilter = [[GPUImageTransformFilter alloc] init];
    [transformFilter setAffineTransform:CGAffineTransformMakeScale(0.5, 0.25)];
//    [(GPUImageTransformFilter *)transformFilter setAffineTransform:CGAffineTransformMakeScale(1.0, 1.0)];
//    [(GPUImageFilterGroup *)filter addFilter:transformFilter];

    GPUImageTransformFilter2 *transformFilter2 = [[GPUImageTransformFilter2 alloc] init];
    [transformFilter2 setAffineTransform:CGAffineTransformMakeScale(2.0, 4.0)];
//    [(GPUImageTransformFilter *)transformFilter2 setAffineTransform:CGAffineTransformMakeScale(1.0, 1.0)];
//    [(GPUImageFilterGroup *)filter addFilter:transformFilter2];

//    GPUImageStretchDistortionFilter *stretchFilter = [[GPUImageStretchDistortionFilter alloc] init];
//    [(GPUImageFilterGroup *)filter addFilter:stretchFilter];

//    NSString *platform = [UIDeviceHardware platformString];

    [(GPUImageFilterGroup *)filter addFilter:transformFilter];
    [(GPUImageFilterGroup *)filter addFilter:transformFilter2];

    if (isFast) {
        GPUImageC64Filter *c64Filter;
        c64Filter = [[GPUImageC64Filter alloc] init];
        [(GPUImageFilterGroup *)filter addFilter:c64Filter];
        [transformFilter addTarget:c64Filter];
        [c64Filter addTarget:transformFilter2];
    } else {
        GPUImageFastC64Filter *c64Filter;
        c64Filter = [[GPUImageFastC64Filter alloc] init];
        [(GPUImageFilterGroup *)filter addFilter:c64Filter];
        [transformFilter addTarget:c64Filter];
        [c64Filter addTarget:transformFilter2];
//        [(GPUImageFilterGroup *)filter addFilter:c64Filter];
//        [transformFilter addTarget:c64Filter];
//        [c64Filter addTarget:transformFilter2];
//        filter = c64Filter;
    }

//    GPUImageC64ColorspaceFilter *c64Filter = [[GPUImageC64ColorspaceFilter alloc] init];
//    GPUImageC64ColorspaceFilter *c64Filter = [[GPUImageAmatorkaFilter alloc] init];
    
    //GPUImagePixellateFilter *pixellateFilter = [[GPUImagePixellateFilter alloc] init];
    //            [(GPUImageFilterGroup *)filter addFilter:pixellateFilter];
    
    
//    GPUImageOverlayBlendFilter *blendFilter = [[GPUImageOverlayBlendFilter alloc] init];
//    UIImage *inputImage;
//    inputImage = [UIImage imageNamed:@"scanline.png"];
//    GPUImagePicture *sourcePicture = [[GPUImagePicture alloc] initWithImage:inputImage smoothlyScaleOutput:NO];
//    [sourcePicture processImage];
//    [sourcePicture addTarget:blendFilter];

//    [(GPUImageFilterGroup *)filter addFilter:blendFilter];
//    [transformFilter2 addTarget:blendFilter];
    
    [(GPUImageFilterGroup *)filter setInitialFilters:[NSArray arrayWithObject:transformFilter]];
    [(GPUImageFilterGroup *)filter setTerminalFilter:transformFilter2];

	[filter prepareForImageCapture];
    
    [stillCamera addTarget:filter];
    GPUImageView *filterView = imageView;
//    [imageView setTransform:CGAffineTransformMakeScale(2.0, 4.0)];
    [filter addTarget:filterView];
    
//    [stillCamera.inputCamera lockForConfiguration:nil];
//    [stillCamera.inputCamera setFlashMode:AVCaptureFlashModeOn];
//    [stillCamera.inputCamera unlockForConfiguration];
    
    [stillCamera startCameraCapture];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (IBAction)updateSliderValue:(id)sender
{
//    [(GPUImagePixellateFilter *)filter setFractionalWidthOfAPixel:[(UISlider *)sender value]];
//    [(GPUImageGammaFilter *)filter setGamma:[(UISlider *)sender value]];
}

- (IBAction)takePhoto:(id)sender;
{
    [photoCaptureButton setEnabled:NO];
//    [imageView setAlpha:0.5];

    CGRect mainScreenFrame = [[UIScreen mainScreen] bounds];

    msgLabel = [[UILabel alloc] initWithFrame:CGRectMake((mainScreenFrame.size.width-200)/2, (mainScreenFrame.size.height-43)/2, 200.0, 43.0)];
    msgLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    msgLabel.textAlignment =  UITextAlignmentCenter;
    msgLabel.textColor = [UIColor whiteColor];
    msgLabel.backgroundColor = [UIColor blackColor];
    msgLabel.alpha = 0.5;
    //        msgLabel.font = [UIFont fontWithName:@"Arial Rounded MT Bold" size:(36.0)];
    msgLabel.text = [NSString stringWithFormat: @"Processing picture..."];
    [imageView addSubview:msgLabel];

    [stillCamera capturePhotoAsJPEGProcessedUpToFilter:filter withCompletionHandler:^(NSData *processedJPEG, NSError *error) {
                
        [stillCamera.captureSession stopRunning];
        
        resultJPEG = processedJPEG;
        
        // Display the image + two buttons to discard or save
        
        UIImage *image = [UIImage imageWithData:resultJPEG];
        if (image.imageOrientation == UIImageOrientationUp) {
            capturedImage = [[UIImageView alloc] initWithImage:image];
        } else {
            UIImage *rotatedImage = [[UIImage alloc] initWithCGImage:image.CGImage scale: 1.0 orientation:UIImageOrientationUp];
            capturedImage = [[UIImageView alloc] initWithImage:rotatedImage];
        }
        if (mainScreenFrame.size.height == 1136/2) {
            [capturedImage setFrame:CGRectMake(0, 20, 320, 426)];
        } else {
            [capturedImage setFrame:CGRectMake(0, 0, 320, 426)];
        }
        
        [self.view addSubview:capturedImage];
        
        UIImage *btnDiscardUp = [UIImage imageNamed:@"discardUp.png"];
        UIImage *btnDiscardDown = [UIImage imageNamed:@"discardDown.png"];
        
        discardButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        [discardButton setTitle:@"Discard" forState:UIControlStateNormal];
        [discardButton addTarget:self action:@selector(discardPhoto:) forControlEvents:UIControlEventTouchUpInside];
        discardButton.frame = CGRectMake(0, mainScreenFrame.size.height - 54.0, mainScreenFrame.size.width / 2, 54.0);

        [discardButton setImage:btnDiscardUp forState:UIControlStateNormal];
        [discardButton setImage:btnDiscardDown forState:UIControlStateHighlighted];

        UIImage *btnSaveUp = [UIImage imageNamed:@"saveUp.png"];
        UIImage *btnSaveDown = [UIImage imageNamed:@"saveDown.png"];

        saveButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        [saveButton setTitle:@"Save" forState:UIControlStateNormal];
        [saveButton addTarget:self action:@selector(savePhoto:) forControlEvents:UIControlEventTouchUpInside];
        saveButton.frame = CGRectMake(round(mainScreenFrame.size.width / 2.0), mainScreenFrame.size.height - 54.0, mainScreenFrame.size.width / 2, 54.0);

        [saveButton setImage:btnSaveUp forState:UIControlStateNormal];
        [saveButton setImage:btnSaveDown forState:UIControlStateHighlighted];

        [self.view addSubview:discardButton];
        [self.view addSubview:saveButton];
        
//        UIAlertView *message = [[UIAlertView alloc] initWithTitle:@"Save Image"
//                                                          message:@"Do you want to keep this picture?"
//                                                         delegate:self
//                                                cancelButtonTitle:@"Cancel"
//                                                otherButtonTitles:@"Save",
//                                nil];
//        [message setAlpha:0.5];
//        [message show];
        
    }];
}

- (IBAction)discardPhoto:(id)sender;
{
    runOnMainQueueWithoutDeadlocking(^{
        //                 report_memory(@"Operation completed");
        [msgLabel removeFromSuperview];
        [capturedImage removeFromSuperview];
        [discardButton removeFromSuperview];
        [saveButton removeFromSuperview];
        //        [imageView setAlpha:1.0];
        [stillCamera.captureSession startRunning];
        [photoCaptureButton setEnabled:YES];
    });
}


- (IBAction)savePhoto:(id)sender;
{
    [msgLabel setText: @"Saving to gallery..."];
        
    // Save to assets library
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    //        report_memory(@"After asset library creation");
    
    [library writeImageDataToSavedPhotosAlbum:resultJPEG metadata:nil completionBlock:^(NSURL *assetURL, NSError *error2) {
         //             report_memory(@"After writing to library");
         if (error2) {
             NSLog(@"ERROR: the image failed to be written");
         }
         else {
             NSLog(@"PHOTO SAVED - assetURL: %@", assetURL);
         }
    }];
         
    runOnMainQueueWithoutDeadlocking(^{
        //                 report_memory(@"Operation completed");
        [msgLabel removeFromSuperview];
        [capturedImage removeFromSuperview];
        [discardButton removeFromSuperview];
        [saveButton removeFromSuperview];
//        [imageView setAlpha:1.0];
        [stillCamera.captureSession startRunning];
        [photoCaptureButton setEnabled:YES];
    });
}

@end
