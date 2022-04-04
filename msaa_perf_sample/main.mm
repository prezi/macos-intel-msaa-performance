//
//  main.m
//  test_capturemanager
//
//  Created by Balint Rikker on 2022. 04. 01..
//

#import <Metal/Metal.h>

#define GL_SILENCE_DEPRECATION
#include <OpenGL/gl.h>
#include <OpenGL/gl3.h>

#include <QuartzCore/QuartzCore.h>

int sampleCount = 4;
int width = 3000, height = 1800;
int numQuads = 100;

struct {
	id<MTLDevice> device;
	id<MTLCommandQueue> commandQueue;
	id<MTLTexture> resolveTexture;
	id<MTLTexture> msaaTexture;
	MTLRenderPassDescriptor* pass;
	id<MTLRenderPipelineState> pipelineState;
} gMetal;

struct {
	CGLContextObj ctx;
	GLuint msaaFBO;
	GLuint msaaTexture;
	GLuint resolveFBO;
	GLuint resolveTexture;
	GLuint timerQuery;
} gOpenGL;

CGLContextObj CreateContext() {
	CGLPixelFormatObj pixelFormat;
	GLint numPixelFormats;

	CGLPixelFormatAttribute attribs[] = {
		kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_Legacy),
		kCGLPFAAccelerated,
		kCGLPFANoRecovery,
		kCGLPFAAllowOfflineRenderers,
		kCGLPFASupportsAutomaticGraphicsSwitching,
		kCGLPFAColorSize, CGLPixelFormatAttribute(32),
		kCGLPFAMinimumPolicy,
		CGLPixelFormatAttribute(0)
	};
	CGLChoosePixelFormat(attribs, &pixelFormat, &numPixelFormats);
	if (!pixelFormat) {
		return nullptr;
	}

	CGLContextObj context = nullptr;
	CGLError error = CGLCreateContext(pixelFormat, nil, &context);
	CGLReleasePixelFormat(pixelFormat);
	if (error != kCGLNoError) {
		return nullptr;
	}
	error = CGLSetCurrentContext(context);
	if (error != kCGLNoError) {
		return nullptr;
	}

	return context;
}

void initMetal() {
	for (id<MTLDevice> dev in MTLCopyAllDevices()) {
		if (dev.isLowPower) {
			gMetal.device = dev;
			break;
		}
    }

    printf("\nMetal device: %s \n", gMetal.device.name.UTF8String);


	gMetal.commandQueue = [gMetal.device newCommandQueue];

	const char *shaderSrc = R"(
using namespace metal;

struct FSIn {
	float4 pos [[position]];
};

vertex FSIn vs_main(uint vid [[vertex_id]]) {
	FSIn output;
	float2 texcoord = float2(vid & 1, vid >> 1);
	float2 pos = texcoord * 2 - 1;
	pos.y *= -1;
	output.pos = float4(pos, 0, 1);
	return output;
}

fragment float4 fs_green(FSIn input [[stage_in]]) {
	return float4(0, 1, 1, 1);
}

)";

	id<MTLLibrary> shaderLib = [gMetal.device newLibraryWithSource:[NSString stringWithUTF8String:shaderSrc]
													 options:[MTLCompileOptions new]
													   error:nil];
	if (!shaderLib) {
		fprintf(stderr, "error creating shader lib\n");
		exit(1);
	}

	MTLRenderPipelineDescriptor* greenPipelineDesc = [MTLRenderPipelineDescriptor new];
	greenPipelineDesc.label = @"green";
	greenPipelineDesc.vertexFunction = [shaderLib newFunctionWithName:@"vs_main"];
	greenPipelineDesc.fragmentFunction = [shaderLib newFunctionWithName:@"fs_green"];
	greenPipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
	greenPipelineDesc.colorAttachments[0].blendingEnabled = NO;
	greenPipelineDesc.sampleCount = sampleCount;

	gMetal.pipelineState = [gMetal.device newRenderPipelineStateWithDescriptor:greenPipelineDesc error:NULL];
	if (!gMetal.pipelineState) {
		fprintf(stderr, "error creating green PSO\n");
		exit(1);
	}

	MTLTextureDescriptor *desc = [MTLTextureDescriptor new];
	desc.pixelFormat = MTLPixelFormatBGRA8Unorm;
	desc.width = width;
	desc.height = height;
	desc.mipmapLevelCount = 1;
	desc.storageMode = MTLStorageModePrivate;
	desc.textureType = MTLTextureType2D;
	desc.usage = MTLTextureUsageRenderTarget;
	gMetal.resolveTexture = [gMetal.device newTextureWithDescriptor:desc];

	MTLTextureDescriptor *msaaDesc = [MTLTextureDescriptor new];
	msaaDesc.pixelFormat = MTLPixelFormatBGRA8Unorm;
	msaaDesc.width = width;
	msaaDesc.height = height;
	msaaDesc.sampleCount = sampleCount;
	msaaDesc.storageMode = MTLStorageModePrivate;
	msaaDesc.textureType = MTLTextureType2DMultisample;
	msaaDesc.usage = MTLTextureUsageRenderTarget;
	gMetal.msaaTexture = [gMetal.device newTextureWithDescriptor:msaaDesc];

	gMetal.pass = [MTLRenderPassDescriptor new];
	gMetal.pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
	gMetal.pass.colorAttachments[0].clearColor = MTLClearColorMake(1, 0, 0, 1);
	gMetal.pass.colorAttachments[0].texture = gMetal.msaaTexture;
	gMetal.pass.colorAttachments[0].resolveTexture = gMetal.resolveTexture;
	gMetal.pass.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
}

void initOpenGL() {
	gOpenGL.ctx = CreateContext();

	printf("\nOpenGL\n");
	printf("* vendor: %s\n", glGetString(GL_VENDOR));
	printf("* renderer: %s\n", glGetString(GL_RENDERER));
	printf("* version: %s\n\n", glGetString(GL_VERSION));

	glGenFramebuffers(1, &gOpenGL.msaaFBO);
	glGenFramebuffers(1, &gOpenGL.resolveFBO);

	glGenQueries(1, &gOpenGL.timerQuery);

	GLuint status;

	glGenRenderbuffers(1, &gOpenGL.msaaTexture);
	glBindRenderbuffer(GL_RENDERBUFFER, gOpenGL.msaaTexture);
	glRenderbufferStorageMultisample(GL_RENDERBUFFER, sampleCount, GL_RGBA8, width, height);

	glBindFramebuffer(GL_FRAMEBUFFER, gOpenGL.msaaFBO);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, gOpenGL.msaaTexture);

	status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
	if (status != GL_FRAMEBUFFER_COMPLETE) {
		exit(1);
	}
	glGenRenderbuffers(1, &gOpenGL.resolveTexture);
	glBindRenderbuffer(GL_RENDERBUFFER, gOpenGL.resolveTexture);
	glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, width, height);

	glBindFramebuffer(GL_FRAMEBUFFER, gOpenGL.resolveFBO);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, gOpenGL.resolveTexture);

	status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
	if (status != GL_FRAMEBUFFER_COMPLETE) {
		exit(1);
	}

	glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

int main(int argc, const char * argv[]) {
	@autoreleasepool {
		initMetal();
		initOpenGL();

		MTLCaptureManager* captureManager = [MTLCaptureManager sharedCaptureManager];
		id<MTLCaptureScope> scp = [captureManager newCaptureScopeWithCommandQueue:gMetal.commandQueue];
		while(1) {
			// in microsecs
			float gpuTimeGL;
			float gpuTimeMTL;

			// metal
			{
				[scp beginScope];

				id<MTLCommandBuffer> commandBuffer = [gMetal.commandQueue commandBuffer];

				// Create a render pass and immediately end encoding, causing the drawable to be cleared
				id<MTLRenderCommandEncoder> commandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:gMetal.pass];

				[commandEncoder setRenderPipelineState:gMetal.pipelineState];
				for (int i = 0; i < numQuads; i++) {
					[commandEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
				}

				[commandEncoder endEncoding];

				[commandBuffer commit];

				[commandBuffer waitUntilCompleted];

				gpuTimeMTL = (commandBuffer.GPUEndTime - commandBuffer.GPUStartTime) * 1000000.;

				[scp endScope];

				[captureManager setDefaultCaptureScope:scp];
			}

			// gl
			{
				glBeginQuery(GL_TIME_ELAPSED, gOpenGL.timerQuery);
				glBindFramebuffer(GL_FRAMEBUFFER, gOpenGL.msaaFBO);
				glViewport(0, 0, width, height);
				glClearColor(0, 1, 0, 1);
				glClear(GL_COLOR_BUFFER_BIT);

				for (int i = 0; i < numQuads; i++) {
					glBegin(GL_QUADS);
					glColor3f(0, (float)i / numQuads, 0);
					glVertex2f(-1, -1);
					glVertex2f(1, -1);
					glVertex2f(1, 1);
					glVertex2f(-1, 1);
					glEnd();
				}

				glBindFramebuffer(GL_READ_FRAMEBUFFER, gOpenGL.msaaFBO);
				glBindFramebuffer(GL_DRAW_FRAMEBUFFER, gOpenGL.resolveFBO);
				glDisable(GL_SCISSOR_TEST);
				glBlitFramebuffer(0, 0, width, height, 0, 0, width, height, GL_COLOR_BUFFER_BIT, GL_NEAREST);

				glEndQuery(GL_TIME_ELAPSED);
				GLuint64 elapsed_time;
				glGetQueryObjectui64v(gOpenGL.timerQuery, GL_QUERY_RESULT, &elapsed_time);

				gpuTimeGL = elapsed_time / 1000.;
			}

			printf("GPU time (usec): MTL: %.2f, GL: %.2f\n", gpuTimeMTL, gpuTimeGL);
		}
	}
	return 0;
}
