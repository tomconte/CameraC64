#import "GPUImageFilter.h"

extern NSString *const kGPUImageThreeInputTextureVertexShaderString;

@interface GPUImageThreeInputFilter : GPUImageFilter
{
    GLint filterSecondTextureCoordinateAttribute;
    GLint filterThirdTextureCoordinateAttribute;
    GLint filterInputTextureUniform2;
    GLint filterInputTextureUniform3;
    GPUImageRotationMode inputRotation2;
    GPUImageRotationMode inputRotation3;
    GLuint filterSourceTexture2;
    GLuint filterSourceTexture3;
    CMTime firstFrameTime, secondFrameTime;
    
    BOOL hasSetFirstTexture, hasReceivedFirstFrame, hasReceivedSecondFrame, firstFrameWasVideo, secondFrameWasVideo;
}

@end
