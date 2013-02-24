#import "PhotoViewController.h"
#import "UIDeviceHardware.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <Social/Social.h>
#import "C64IAPHelper.h"
#import "Flurry.h"

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
    // Is this an iPhone 5?
	CGRect mainScreenFrame = [[UIScreen mainScreen] bounds];
    iPhone5 = (mainScreenFrame.size.height == 1136/2);
    	   
    // Yes, I know I'm a caveman for doing all this by hand
	UIView *primaryView = [[UIView alloc] initWithFrame:mainScreenFrame];
	primaryView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    if (mainScreenFrame.size.height == 1136/2) {
        imageView = [[GPUImageView alloc] initWithFrame:CGRectMake(0, 20, 640/2, 852/2)];
    } else {
        imageView = [[GPUImageView alloc] initWithFrame:CGRectMake(0, 0, 640/2, 852/2)];
    }

    [primaryView addSubview:imageView];
    
    // Title bar
    
    UIImage *titleBarImage = [UIImage imageNamed:@"newtitlebar.png"];

    titleBar = [UIButton buttonWithType:UIButtonTypeCustom];
    [titleBar setImage:titleBarImage forState:UIControlStateNormal];
    [titleBar setImage:titleBarImage forState:UIControlStateHighlighted];
    [titleBar setFrame:CGRectMake(0, 0, mainScreenFrame.size.width, 20)];
    titleBar.adjustsImageWhenDisabled = NO;
    [titleBar addTarget:self action:@selector(switchScreen:) forControlEvents:UIControlEventTouchUpInside];

    [primaryView addSubview:titleBar];

    // Rotate camera

    if( [UIImagePickerController isCameraDeviceAvailable: UIImagePickerControllerCameraDeviceFront ]) {
        UIImage *rotateImage = [UIImage imageNamed:@"reverse-back.png"];
        
        rotateButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [rotateButton setImage:rotateImage forState:UIControlStateNormal];
        [rotateButton setImage:rotateImage forState:UIControlStateHighlighted];
        [rotateButton setFrame:CGRectMake(mainScreenFrame.size.width - 120/2, 0, 120/2, 120/2)];
        rotateButton.adjustsImageWhenDisabled = NO;
        [rotateButton addTarget:self action:@selector(switchCamera:) forControlEvents:UIControlEventTouchUpInside];
        
        [primaryView addSubview:rotateButton];
    }

    if (iPhone5) {
        
        // Power bar
        
        UIImage *btnPowerBar = [UIImage imageNamed:@"power-568h@2x.png"];
        
        powerBar = [UIButton buttonWithType:UIButtonTypeCustom];
        [powerBar setImage:btnPowerBar forState:UIControlStateNormal];
        [powerBar setImage:btnPowerBar forState:UIControlStateHighlighted];
        [powerBar setFrame:CGRectMake(0, mainScreenFrame.size.height - 72 - 50,
                                      mainScreenFrame.size.width, 50)];
        powerBar.adjustsImageWhenDisabled = NO;
        [powerBar addTarget:self action:@selector(switchScreen:) forControlEvents:UIControlEventTouchUpInside];
        
        [primaryView addSubview:powerBar];

        // Photo capture
        
        UIImage *btnImageUp = [UIImage imageNamed:@"capture-up-568h@2x.png"];
        UIImage *btnImageDown = [UIImage imageNamed:@"capture-down-568h@2x.png"];
        
        photoCaptureButton = [UIButton buttonWithType:UIButtonTypeCustom];
        photoCaptureButton.frame = CGRectMake(90, mainScreenFrame.size.height - 72,
                                              135, 72);
        [photoCaptureButton setImage:btnImageUp forState:UIControlStateNormal];
        [photoCaptureButton setImage:btnImageDown forState:UIControlStateHighlighted];
        photoCaptureButton.adjustsImageWhenDisabled = NO;
        photoCaptureButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
        [photoCaptureButton addTarget:self action:@selector(takePhoto:) forControlEvents:UIControlEventTouchUpInside];
        
        [primaryView addSubview:photoCaptureButton];
        
        // Change filter

        UIImage *btnImageFilter = [UIImage imageNamed:@"monitor-color-568h@2x.png"];
        
        changeFilterButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [changeFilterButton setImage:btnImageFilter forState:UIControlStateNormal];
        [changeFilterButton setImage:btnImageFilter forState:UIControlStateHighlighted];
        changeFilterButton.frame = CGRectMake(0, mainScreenFrame.size.height - 72,
                                              90, 72);
        changeFilterButton.adjustsImageWhenDisabled = NO;
        [changeFilterButton addTarget:self action:@selector(changeFilter:)
                     forControlEvents:UIControlEventTouchUpInside];
        [primaryView addSubview:changeFilterButton];
        
        // Flash & scanline

        UIImage *btnImageFlash = [UIImage imageNamed:@"flash-off-568h@2x.png"];
        
        flashButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [flashButton setImage:btnImageFlash forState:UIControlStateNormal];
        [flashButton setImage:btnImageFlash forState:UIControlStateHighlighted];
        flashButton.frame = CGRectMake(135 + 90, mainScreenFrame.size.height - 72,
                                              95, 32);
        flashButton.adjustsImageWhenDisabled = NO;
        [flashButton addTarget:self action:@selector(switchFlash:)
                     forControlEvents:UIControlEventTouchUpInside];
        [primaryView addSubview:flashButton];

        UIImage *btnImageScanline = [UIImage imageNamed:@"scanline-off-568h@2x.png"];
        
        scanlineButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [scanlineButton setImage:btnImageScanline forState:UIControlStateNormal];
        [scanlineButton setImage:btnImageScanline forState:UIControlStateHighlighted];
        scanlineButton.frame = CGRectMake(135 + 90, mainScreenFrame.size.height - 40,
                                       95, 40);
        scanlineButton.adjustsImageWhenDisabled = NO;
        [scanlineButton addTarget:self action:@selector(switchScanline:)
              forControlEvents:UIControlEventTouchUpInside];
        [primaryView addSubview:scanlineButton];

    } else {

        // Photo capture
        
        UIImage *btnImageUp = [UIImage imageNamed:@"capture-up.png"];
        UIImage *btnImageDown = [UIImage imageNamed:@"capture-down.png"];
        
        photoCaptureButton = [UIButton buttonWithType:UIButtonTypeCustom];
        photoCaptureButton.frame = CGRectMake(90, mainScreenFrame.size.height - 54,
                                              135, 54);
        [photoCaptureButton setImage:btnImageUp forState:UIControlStateNormal];
        [photoCaptureButton setImage:btnImageDown forState:UIControlStateHighlighted];
        photoCaptureButton.adjustsImageWhenDisabled = NO;
        photoCaptureButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
        [photoCaptureButton addTarget:self action:@selector(takePhoto:) forControlEvents:UIControlEventTouchUpInside];
        
        [primaryView addSubview:photoCaptureButton];
        
        // Change filter
        
        UIImage *btnImageFilter = [UIImage imageNamed:@"monitor-color.png"];
        
        changeFilterButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [changeFilterButton setImage:btnImageFilter forState:UIControlStateNormal];
        [changeFilterButton setImage:btnImageFilter forState:UIControlStateHighlighted];
        changeFilterButton.frame = CGRectMake(0, mainScreenFrame.size.height - 54,
                                              90, 54);
        changeFilterButton.adjustsImageWhenDisabled = NO;
        [changeFilterButton addTarget:self action:@selector(changeFilter:)
                     forControlEvents:UIControlEventTouchUpInside];
        [primaryView addSubview:changeFilterButton];
        
        // Flash & scanline
        
        UIImage *btnImageFlash = [UIImage imageNamed:@"flash-off.png"];
        
        flashButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [flashButton setImage:btnImageFlash forState:UIControlStateNormal];
        [flashButton setImage:btnImageFlash forState:UIControlStateHighlighted];
        flashButton.frame = CGRectMake(135 + 90, mainScreenFrame.size.height - 54,
                                       95, 27);
        flashButton.adjustsImageWhenDisabled = NO;
        [flashButton addTarget:self action:@selector(switchFlash:)
              forControlEvents:UIControlEventTouchUpInside];
        [primaryView addSubview:flashButton];
        
        UIImage *btnImageScanline = [UIImage imageNamed:@"scanline-off.png"];
        
        scanlineButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [scanlineButton setImage:btnImageScanline forState:UIControlStateNormal];
        [scanlineButton setImage:btnImageScanline forState:UIControlStateHighlighted];
        scanlineButton.frame = CGRectMake(135 + 90, mainScreenFrame.size.height - 27,
                                          95, 27);
        scanlineButton.adjustsImageWhenDisabled = NO;
        [scanlineButton addTarget:self action:@selector(switchScanline:)
              forControlEvents:UIControlEventTouchUpInside];
        [primaryView addSubview:scanlineButton];

    }
    
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
//        c64Filter = [[GPUImageC64Filter alloc] init];
        c64Filter = [[GPUImageC64Filter alloc] initWithCLUT1:@"paletteC64_first.png" andCLUT2:@"paletteC64_second.png"];
        [(GPUImageFilterGroup *)filter addFilter:c64Filter];
        [transformFilter addTarget:c64Filter];
        [c64Filter addTarget:transformFilter2];
    } else {
        GPUImageFastC64Filter *c64Filter;
        c64Filter = [[GPUImageFastC64Filter alloc] initWithCLUT:@"paletteC64_first.png"];
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

- (void)viewWillAppear:(BOOL)animated {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(productPurchased:) name:IAPHelperProductPurchasedNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)productPurchased:(NSNotification *)notification {
    
    NSString * productIdentifier = notification.object;
    [_products enumerateObjectsUsingBlock:^(SKProduct * product, NSUInteger idx, BOOL *stop) {
        if ([product.productIdentifier isEqualToString:productIdentifier]) {
            UIAlertView *message = [[UIAlertView alloc] initWithTitle:product.localizedTitle
                                                              message:@"Thank you for buying! The feature is now enabled."
                                                             delegate:self
                                                    cancelButtonTitle:@"OK"
                                    otherButtonTitles:nil];
            [message setAlpha:0.5];
            [message show];
        }
    }];
    
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (IBAction)takePhoto:(id)sender;
{
    [Flurry logEvent:@"Photo_Take"];

    // Disable buttons
    photoCaptureButton.enabled = NO;
    changeFilterButton.enabled = NO;
    scanlineButton.enabled = NO;
    flashButton.enabled = NO;
    titleBar.enabled = NO;
    powerBar.enabled = NO;

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

    [stillCamera capturePhotoAsImageProcessedUpToFilter:filter withCompletionHandler:^(UIImage *processedImage, NSError *error) {
                
        [stillCamera.captureSession stopRunning];
        
        // Reorient
        
        UIImage *bottomImage;

        if (processedImage.imageOrientation == UIImageOrientationUp) {
            bottomImage = processedImage;
        } else {
            UIImage *rotatedImage = [[UIImage alloc] initWithCGImage:processedImage.CGImage scale: 1.0 orientation:UIImageOrientationUp];
            bottomImage = rotatedImage;
        }
        
        // Merge scanlines
        
        UIImage *newImage;
        
        if (scanlineOn) {
            UIImage *image = [UIImage imageNamed:@"scanline-vertical.png"]; //foreground image        
            CGSize newSize = CGSizeMake(bottomImage.size.width, bottomImage.size.height);
            UIGraphicsBeginImageContext(newSize);
            [bottomImage drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
            [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height) blendMode:kCGBlendModeNormal alpha:0.8];
            newImage = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        } else {
            newImage = bottomImage;
        }

        // The image to display
        
        capturedImage = [[UIImageView alloc] initWithImage:newImage];

        // Now restore the original orientation if necessary before generating the result JPEG
        
        if (processedImage.imageOrientation == UIImageOrientationUp) {
            resultJPEG = UIImageJPEGRepresentation(newImage, 0.80);
        } else {
            UIImage *rotatedImage = [[UIImage alloc] initWithCGImage:newImage.CGImage scale: 1.0 orientation:processedImage.imageOrientation];
            resultJPEG = UIImageJPEGRepresentation(rotatedImage, 0.80);
        }
        
        // Display the image
        
        if (mainScreenFrame.size.height == 1136/2) {
            [capturedImage setFrame:CGRectMake(0, 20, 320, 426)];
        } else {
            [capturedImage setFrame:CGRectMake(0, 0, 320, 426)];
        }
        
        [self.view addSubview:capturedImage];

        // iOS 6 : discard / share
        // iOS 5 : discard / save

        discardButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        [discardButton setTitle:@"Discard" forState:UIControlStateNormal];
        [discardButton addTarget:self action:@selector(discardPhoto:) forControlEvents:UIControlEventTouchUpInside];

        saveButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        [saveButton setTitle:@"Save" forState:UIControlStateNormal];

        UIImage *btnDiscardUp;
        UIImage *btnDiscardDown;

        UIImage *btnSaveUp;
        UIImage *btnSaveDown;
        
        if (iPhone5) {
            btnDiscardUp = [UIImage imageNamed:@"discard-up-568h@2x.png"];
            btnDiscardDown = [UIImage imageNamed:@"discard-down-568h@2x.png"];
            btnSaveUp = [UIImage imageNamed:@"share-up-568h@2x.png"];
            btnSaveDown = [UIImage imageNamed:@"share-down-568h@2x.png"];
            
            discardButton.frame = CGRectMake(90, mainScreenFrame.size.height - 72, 68, 72);
            
            [discardButton setImage:btnDiscardUp forState:UIControlStateNormal];
            [discardButton setImage:btnDiscardDown forState:UIControlStateHighlighted];
            
            saveButton.frame = CGRectMake(90 + 68, mainScreenFrame.size.height - 72, 67, 72);
            
            [saveButton setImage:btnSaveUp forState:UIControlStateNormal];
            [saveButton setImage:btnSaveDown forState:UIControlStateHighlighted];

            // iPhone 5 == iOS 6, call the share action
            [saveButton addTarget:self action:@selector(sharePhoto:) forControlEvents:UIControlEventTouchUpInside];
        } else {
            btnDiscardUp = [UIImage imageNamed:@"discard-up.png"];
            btnDiscardDown = [UIImage imageNamed:@"discard-down.png"];
            btnSaveUp = [UIImage imageNamed:@"share-up.png"];
            btnSaveDown = [UIImage imageNamed:@"share-down.png"];

            discardButton.frame = CGRectMake(90, mainScreenFrame.size.height - 54, 68, 54);
            
            [discardButton setImage:btnDiscardUp forState:UIControlStateNormal];
            [discardButton setImage:btnDiscardDown forState:UIControlStateHighlighted];
            
            saveButton.frame = CGRectMake(90 + 68, mainScreenFrame.size.height - 54, 67, 54);
            
            [saveButton setImage:btnSaveUp forState:UIControlStateNormal];
            [saveButton setImage:btnSaveDown forState:UIControlStateHighlighted];

            // For all other iPhone models, iOS5 / iOS6
            int iOSVersion = [[[UIDevice currentDevice] systemVersion] intValue];
            if (iOSVersion > 5) {
                [saveButton addTarget:self action:@selector(sharePhoto:) forControlEvents:UIControlEventTouchUpInside];
            } else {
                [saveButton addTarget:self action:@selector(savePhoto:) forControlEvents:UIControlEventTouchUpInside];
            }
        }

        [self.view addSubview:discardButton];
        [self.view addSubview:saveButton];

    }];
}

- (IBAction)discardPhoto:(id)sender;
{
    [Flurry logEvent:@"Photo_Discard"];

    runOnMainQueueWithoutDeadlocking(^{
        //                 report_memory(@"Operation completed");
        [msgLabel removeFromSuperview];
        [capturedImage removeFromSuperview];
        [discardButton removeFromSuperview];
        [saveButton removeFromSuperview];
        
        [stillCamera.captureSession startRunning];
        
        // Enable buttons
        photoCaptureButton.enabled = YES;
        changeFilterButton.enabled = YES;
        scanlineButton.enabled = YES;
        flashButton.enabled = YES;
        titleBar.enabled = YES;
        powerBar.enabled = YES;
    });
}


- (IBAction)savePhoto:(id)sender;
{
    [Flurry logEvent:@"Photo_Save"];

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
        
        [stillCamera.captureSession startRunning];

        // Enable buttons
        photoCaptureButton.enabled = YES;
        changeFilterButton.enabled = YES;
        scanlineButton.enabled = YES;
        flashButton.enabled = YES;
        titleBar.enabled = YES;
        powerBar.enabled = YES;
    });
}

- (IBAction)sharePhoto:(id)sender;
{
    [Flurry logEvent:@"Photo_Share"];

    NSArray *activityItems;
    
    activityItems = @[resultJPEG];
    
    UIActivityViewController *activityController = [[UIActivityViewController alloc] initWithActivityItems:activityItems applicationActivities:nil];
    
    [self presentViewController:activityController animated:YES completion:nil];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    NSString *title = [alertView buttonTitleAtIndex:buttonIndex];
    if([title isEqualToString:@"Purchase"])
    {
        [Flurry logEvent:@"InApp_Purchase"];

        SKProduct *product = _products[0]; // Only one product ...
        [[C64IAPHelper sharedInstance] buyProduct:product];
    }
    else if([title isEqualToString:@"Restore"])
    {
        [Flurry logEvent:@"InApp_Restore"];

        [[C64IAPHelper sharedInstance] restoreCompletedTransactions];
    }
}

- (IBAction)changeFilter:(id)sender;
{
    [Flurry logEvent:@"Filter_Change"];
    
    GLint maxTextureSize = [GPUImageOpenGLESContext maximumTextureSizeForThisDevice];
    bool isFast = (maxTextureSize > 2048);

    NSArray *paletteFirst = @[ @"paletteC64_first.png", @"b&w_paletteC64_first.png", @"amber_paletteC64_first.png", @"green_paletteC64_first.png" ];
    NSArray *paletteSecond = @[ @"paletteC64_second.png", @"b&w_paletteC64_second.png", @"amber_paletteC64_second.png", @"green_paletteC64_second.png" ];
    NSArray *filterNames;
    
    if (iPhone5) {
        filterNames = @[ @"monitor-color-568h@2x.png", @"monitor-b&w-568h@2x.png", @"monitor-amber-568h@2x.png", @"monitor-green-568h@2x.png" ];
    } else {
        filterNames = @[ @"monitor-color.png", @"monitor-b&w.png", @"monitor-amber.png", @"monitor-green.png" ];
    }
    
    if ([[C64IAPHelper sharedInstance] productPurchased:@"AXOLINK_C64_FILTERS"] == NO) {
        
        // Retrieve product information from App Store
        [[C64IAPHelper sharedInstance] requestProductsWithCompletionHandler:^(BOOL success, NSArray *products) {
            if (success) {
                [Flurry logEvent:@"InApp_Dialog"];

                _products = products;
                
                SKProduct *product = (SKProduct *)_products[0]; // Only one product ...
                
                NSNumberFormatter *_priceFormatter = [[NSNumberFormatter alloc] init];
                [_priceFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
                [_priceFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
                [_priceFormatter setLocale:product.priceLocale];
                
                NSString *msg = [NSString stringWithFormat:@"Do you want to purchase %@ for %@ ?", product.localizedDescription, [_priceFormatter stringFromNumber:product.price]];
                
                // Display alert message
                UIAlertView *message = [[UIAlertView alloc] initWithTitle:product.localizedTitle
                                                                  message:msg
                                                                 delegate:self
                                                        cancelButtonTitle:@"Cancel"
                                                        otherButtonTitles:@"Purchase", @"Restore",
                                        nil];
                [message setAlpha:0.5];
                [message show];
            }
        }];

        return;
    }
    
    // Increment filter counter
    
    curFilter = ++curFilter % 4;
    
    // Change filter button picture

    UIImage *btnImageFilter = [UIImage imageNamed:filterNames[curFilter]];
    [changeFilterButton setImage:btnImageFilter forState:UIControlStateNormal];
    [changeFilterButton setImage:btnImageFilter forState:UIControlStateHighlighted];

    // Try and remove old filter
    
    [stillCamera stopCameraCapture];
    [stillCamera removeAllTargets];
    [filter removeAllTargets];
    
    // Create new filter
    
//    stillCamera = [[GPUImageStillCamera alloc] initWithSessionPreset:AVCaptureSessionPreset640x480 cameraPosition:AVCaptureDevicePositionBack];
//    stillCamera.outputImageOrientation = UIInterfaceOrientationPortrait;
    
    filter = [[GPUImageFilterGroup alloc] init];
    
    GPUImageTransformFilter *transformFilter = [[GPUImageTransformFilter alloc] init];
    [transformFilter setAffineTransform:CGAffineTransformMakeScale(0.5, 0.25)];
    
    GPUImageTransformFilter2 *transformFilter2 = [[GPUImageTransformFilter2 alloc] init];
    [transformFilter2 setAffineTransform:CGAffineTransformMakeScale(2.0, 4.0)];
    
    [(GPUImageFilterGroup *)filter addFilter:transformFilter];
    [(GPUImageFilterGroup *)filter addFilter:transformFilter2];
    
    if (isFast) {
        GPUImageC64Filter *c64Filter;
        c64Filter = [[GPUImageC64Filter alloc] initWithCLUT1:paletteFirst[curFilter] andCLUT2:paletteSecond[curFilter]];
        [(GPUImageFilterGroup *)filter addFilter:c64Filter];
        [transformFilter addTarget:c64Filter];
        [c64Filter addTarget:transformFilter2];
    } else {
        GPUImageFastC64Filter *c64Filter;
        c64Filter = [[GPUImageFastC64Filter alloc] initWithCLUT:paletteFirst[curFilter]];
        [(GPUImageFilterGroup *)filter addFilter:c64Filter];
        [transformFilter addTarget:c64Filter];
        [c64Filter addTarget:transformFilter2];
    }
    
    [(GPUImageFilterGroup *)filter setInitialFilters:[NSArray arrayWithObject:transformFilter]];
    [(GPUImageFilterGroup *)filter setTerminalFilter:transformFilter2];
    
	[filter prepareForImageCapture];
    
    [stillCamera addTarget:filter];
    GPUImageView *filterView = imageView;
    [filter addTarget:filterView];
    
    [stillCamera startCameraCapture];
}

- (IBAction)switchFlash:(id)sender;
{
    [Flurry logEvent:@"Flash_Switch"];

    if ([stillCamera.inputCamera hasFlash]) {
        [stillCamera.inputCamera lockForConfiguration:nil];
        if ([stillCamera.inputCamera flashMode] == AVCaptureFlashModeOff) {
            [stillCamera.inputCamera setFlashMode:AVCaptureFlashModeOn];
            UIImage *btnImageFlash;
            if (iPhone5) {
                btnImageFlash = [UIImage imageNamed:@"flash-on-568h@2x.png"];
            } else {
                btnImageFlash = [UIImage imageNamed:@"flash-on.png"];
            }
            [flashButton setImage:btnImageFlash forState:UIControlStateNormal];
            [flashButton setImage:btnImageFlash forState:UIControlStateHighlighted];
            
        } else {
            [stillCamera.inputCamera setFlashMode:AVCaptureFlashModeOff];
            UIImage *btnImageFlash;
            if (iPhone5) {
                btnImageFlash = [UIImage imageNamed:@"flash-off-568h@2x.png"];
            } else {
                btnImageFlash = [UIImage imageNamed:@"flash-off.png"];
            }
            [flashButton setImage:btnImageFlash forState:UIControlStateNormal];
            [flashButton setImage:btnImageFlash forState:UIControlStateHighlighted];
        }
        [stillCamera.inputCamera unlockForConfiguration];
    }
}

- (IBAction)switchScanline:(id)sender;
{
    [Flurry logEvent:@"Scanline_Switch"];

    if (!scanlineOn) {
        scanlineOn = YES;
        UIImage *btnImageScanline;
        if (iPhone5) {
            btnImageScanline = [UIImage imageNamed:@"scanline-on-568h@2x.png"];
        } else {
            btnImageScanline = [UIImage imageNamed:@"scanline-on.png"];
        }
        [scanlineButton setImage:btnImageScanline forState:UIControlStateNormal];
        [scanlineButton setImage:btnImageScanline forState:UIControlStateHighlighted];
        
        if (!imageScanlineView) {
            if (iPhone5) {
                imageScanlineView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"scanline-568h@2x.png"]];
                [imageScanlineView setFrame:CGRectMake(0, 20, 640/2, 852/2)];
            } else {
                imageScanlineView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"scanline.png"]];
                [imageScanlineView setFrame:CGRectMake(0, 20, 640/2, 812/2)];
            }
        }
        
        [self.view addSubview:imageScanlineView];

    } else {
        scanlineOn = NO;
        UIImage *btnImageScanline;
        if (iPhone5) {
            btnImageScanline = [UIImage imageNamed:@"scanline-off-568h@2x.png"];
        } else {
            btnImageScanline = [UIImage imageNamed:@"scanline-off.png"];
        }
        [scanlineButton setImage:btnImageScanline forState:UIControlStateNormal];
        [scanlineButton setImage:btnImageScanline forState:UIControlStateHighlighted];
        
        [imageScanlineView removeFromSuperview];
    }
}

- (IBAction)switchScreen:(id)sender;
{
    [Flurry logEvent:@"Screen_Switch"];

    UIImage *toImage;
    UIImage *fromImage;
    
    NSArray *fromImages;
    NSArray *toImages;
    
    if (iPhone5) {
        fromImages = @[ @"color-off-beam-568h@2x.png", @"b&w-off-beam-568h@2x.png", @"amber-off-beam-568h@2x.png", @"green-off-beam-568h@2x.png" ];
        toImages = @[ @"color-off-568h@2x.png", @"b&w-off-568h@2x.png", @"amber-off-568h@2x.png", @"green-off-568h@2x.png" ];
    } else {
        fromImages = @[ @"color-off-beam.png", @"b&w-off-beam.png", @"amber-off-beam.png", @"green-off-beam.png" ];
        toImages = @[ @"color-off.png", @"b&w-off.png", @"amber-off.png", @"green-off.png" ];
    }

    if (isScreenOff) {
        
        isScreenOff = NO;
        
        [imageScreen removeFromSuperview];
        imageScreen = nil;
        
        // Reset button actions
        [photoCaptureButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [changeFilterButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [scanlineButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [flashButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];

        [photoCaptureButton addTarget:self action:@selector(takePhoto:) forControlEvents:UIControlEventTouchUpInside];
        [changeFilterButton addTarget:self action:@selector(changeFilter:) forControlEvents:UIControlEventTouchUpInside];
        [flashButton addTarget:self action:@selector(switchFlash:) forControlEvents:UIControlEventTouchUpInside];
        [scanlineButton addTarget:self action:@selector(switchScanline:) forControlEvents:UIControlEventTouchUpInside];

    } else {
        
        isScreenOff = YES;
        
        // Change button actions
        [photoCaptureButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [changeFilterButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [scanlineButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [flashButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];

        [photoCaptureButton addTarget:self action:@selector(switchScreen:) forControlEvents:UIControlEventTouchUpInside];
        [changeFilterButton addTarget:self action:@selector(switchScreen:) forControlEvents:UIControlEventTouchUpInside];
        [scanlineButton addTarget:self action:@selector(switchScreen:) forControlEvents:UIControlEventTouchUpInside];
        [flashButton addTarget:self action:@selector(switchScreen:) forControlEvents:UIControlEventTouchUpInside];
        
        fromImage = [UIImage imageNamed:fromImages[curFilter]];
        toImage = [UIImage imageNamed:toImages[curFilter]];

        if (!imageScreen) {
            if (iPhone5) {
                imageScreen = [[UIImageView alloc] initWithImage:fromImage];
                [imageScreen setFrame:CGRectMake(0, 20, 640/2, 852/2)];
            } else {
                imageScreen = [[UIImageView alloc] initWithImage:fromImage];
                [imageScreen setFrame:CGRectMake(0, 20, 640/2, 812/2)];
            }
        }
        
        CABasicAnimation *crossFade = [CABasicAnimation animationWithKeyPath:@"contents"];
        crossFade.duration = 1.0;
        crossFade.fromValue = (id)(fromImage.CGImage);
        crossFade.toValue = (id)(toImage.CGImage);
        [imageScreen.layer addAnimation:crossFade forKey:@"animateContents"];
        [imageScreen setImage:toImage];
        
        [self.view addSubview:imageScreen];
    }
}

- (IBAction)switchCamera:(id)sender;
{
    [stillCamera rotateCamera];
    
    if (isFrontCamera) {
        UIImage *rotateImage = [UIImage imageNamed:@"reverse-back.png"];        
        [rotateButton setImage:rotateImage forState:UIControlStateNormal];
        [rotateButton setImage:rotateImage forState:UIControlStateHighlighted];
    } else {
        UIImage *rotateImage = [UIImage imageNamed:@"reverse-front.png"];
        [rotateButton setImage:rotateImage forState:UIControlStateNormal];
        [rotateButton setImage:rotateImage forState:UIControlStateHighlighted];
    }
    
    isFrontCamera = !isFrontCamera;
}

@end
