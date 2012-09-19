#import "GPUImage8BitLookupFilter.h"

NSString *const kGPUImageLookupFragmentShaderString8bit = SHADER_STRING
(
 varying highp vec2 textureCoordinate;
 varying highp vec2 textureCoordinate2; // TODO: This is not used
 varying highp vec2 textureCoordinate3; // TODO: This is not used
 
 uniform sampler2D inputImageTexture;
 uniform sampler2D inputImageTexture2; // lookup texture
 uniform sampler2D inputImageTexture3; // lookup texture
 
 mediump vec4 dither[4];
 
 highp float find_closest(int x, int y, highp float c0)
 {
     highp float limit = 0.0;
     if (x < 4)
     {
         limit = (dither[x][y]+1.0)/64.0;
     }
     
     if (c0 < limit)
         return 0.0;
     
     return 1.0;
 }
 
 void main()
 {
     dither[0] = vec4( 1.0, 33.0, 9.0, 41.0);
     dither[1] = vec4(49.0, 17.0, 57.0, 25.0);
     dither[2] = vec4(13.0, 45.0, 5.0, 37.0);
     dither[3] = vec4(61.0, 29.0, 53.0, 21.0);
     
     mediump vec2 xy = gl_FragCoord.xy;
     int x = int(mod(xy.x, 4.0));
     int y = int(mod(xy.y, 4.0));

//     highp vec2 sampleDivisor = vec2(1.0/160.0, 1.0/100.0);
//     highp vec2 samplePos = textureCoordinate - mod(textureCoordinate, sampleDivisor) + 0.5 * sampleDivisor;

     lowp vec4 textureColor = texture2D(inputImageTexture, textureCoordinate);
     
     mediump float blueColor = textureColor.b * 63.0;
     
     mediump vec2 quad1;
     quad1.y = floor(floor(blueColor) / 8.0);
     quad1.x = floor(blueColor) - (quad1.y * 8.0);
     
     mediump vec2 quad2;
     quad2.y = floor(ceil(blueColor) / 8.0);
     quad2.x = ceil(blueColor) - (quad2.y * 8.0);
     
     highp vec2 texPos1;
     texPos1.x = (quad1.x * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * textureColor.r);
     texPos1.y = (quad1.y * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * textureColor.g);
     
     highp vec2 texPos2;
     texPos2.x = (quad2.x * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * textureColor.r);
     texPos2.y = (quad2.y * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * textureColor.g);
     
     lowp vec4 newColor1;
     lowp vec4 newColor2;

     newColor1 = texture2D(inputImageTexture2, texPos1);
     newColor2 = texture2D(inputImageTexture2, texPos2);

     if (find_closest(x, y, distance(textureColor, newColor1)) != 0.0) {
         newColor1 = texture2D(inputImageTexture3, texPos1);
         newColor2 = texture2D(inputImageTexture3, texPos2);
     }
     
     lowp vec4 newColor = mix(newColor1, newColor2, fract(blueColor));
     gl_FragColor = vec4(newColor.rgb, textureColor.w);
 }
);

@implementation GPUImage8BitLookupFilter

- (id)init;
{
    if (!(self = [super initWithFragmentShaderFromString:kGPUImageLookupFragmentShaderString8bit]))
    {
		return nil;
    }
    
    return self;
}

@end
