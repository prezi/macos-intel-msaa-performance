# macos-intel-msaa-performance
A sample Xcode project to demonstrate 4-6 times slower MSAA performance on Intel iGPUs with Metal compared to OpenGL

This project intends to demonstrate a possible bug in Intel GPU Metal drivers that causes MSAA to be several times slower than running on the same GPU with OpenGL.

The issue has been reproduced in-house on three different MacBook Pros (2017, 2018, 2019) and macOS versions (11.3.1, 12.2.1, 10.15.7).

The same performance different does not occur on the dedicated GPUs of the same machines.

The sample application does offscreen rendering, drawing single-color fullscreen quads.
It performs offscreen rendering to eliminate any scheduling effects from the compositor, executing a single render pass in a single command buffer.
The pass consists of drawing a selectable number of fullscreen quads with constant color.
No depth/stencil attachments, blending is disabled.

## Build steps
- Open the `msaa_perf_sample.xcodeproj` project in Xcode.
- Ensure that only the integrated GPU is used for graphics rendering, e. g. by setting it in [gfxCardStatus](https://gfx.io/)
- Build and run the `msaa_perf_sample` target.

The application then repeatedly renders offscreen quads using both Metal and OpenGL until stopped. In each iteration, it prints the timing results in microseconds to the console.

Sample output:
```
Metal device: Intel(R) HD Graphics 630 

OpenGL
* vendor: Intel Inc.
* renderer: Intel(R) HD Graphics 630
* version: 2.1 INTEL-16.2.16


GPU time (usec): MTL: 705004.81, GL: 163427.92
GPU time (usec): MTL: 654540.19, GL: 155161.33
GPU time (usec): MTL: 647487.44, GL: 148531.00
GPU time (usec): MTL: 652132.44, GL: 152898.92
GPU time (usec): MTL: 653307.81, GL: 156711.17
```

## Metal frame capture
The Frame Capture utility of Xcode's Metal profiler can be used to record perfomance data of a single iteration.
The GPU trace of one such frame capture can be seen in `msaa_perf_sample.gputrace`.
