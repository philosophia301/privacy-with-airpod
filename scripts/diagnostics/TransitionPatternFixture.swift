import AppKit
import MetalKit

/// 실제 앱의 GPU 표면과 일반 NSView 그리기를 같은 줄무늬 입력으로 비교함.
@MainActor final class MetalFixtureView: MTKView, MTKViewDelegate {
 private var commands: MTLCommandQueue!
 private var pipeline: MTLRenderPipelineState!
 private let tint: SIMD4<Float>
 init(frame: CGRect, color: NSColor) throws {
  let rgb = color.usingColorSpace(.deviceRGB)!
  tint = SIMD4(Float(rgb.redComponent), Float(rgb.greenComponent), Float(rgb.blueComponent), 1)
  guard let device = MTLCreateSystemDefaultDevice() else { throw NSError(domain:"Fixture",code:1) }
  super.init(frame:frame,device:device)
  guard let queue = device.makeCommandQueue() else { throw NSError(domain:"Fixture",code:2) }
  commands = queue
  let source = """
  #include <metal_stdlib>
  using namespace metal;
  vertex float4 fixtureVertex(uint i [[vertex_id]]) {
   float2 p[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
   return float4(p[i],0,1);
  }
  fragment float4 fixtureFragment(float4 p [[position]], constant float4 &tint [[buffer(0)]], constant float &scale [[buffer(1)]]) {
   float factor = uint(p.x / (8 * scale)) % 2 == 0 ? 0.3 : 1.0;
   return float4(tint.rgb * factor, 1);
  }
  """
  let library = try device.makeLibrary(source:source,options:nil)
  let descriptor = MTLRenderPipelineDescriptor()
  descriptor.vertexFunction = library.makeFunction(name:"fixtureVertex")
  descriptor.fragmentFunction = library.makeFunction(name:"fixtureFragment")
  descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
  pipeline = try device.makeRenderPipelineState(descriptor:descriptor)
  preferredFramesPerSecond = 60
  delegate = self
 }
 required init(coder: NSCoder) { fatalError() }
 func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
 func draw(in view: MTKView) {
  guard let drawable = currentDrawable, let pass = currentRenderPassDescriptor,
        let buffer = commands.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor:pass) else {
   fputs("FAIL Metal fixture drawable/command unavailable\n",stderr); exit(1)
  }
  var color = tint
  var scale = Float(drawableSize.width / max(1,bounds.width))
  encoder.setRenderPipelineState(pipeline)
  encoder.setFragmentBytes(&color,length:MemoryLayout.size(ofValue:color),index:0)
  encoder.setFragmentBytes(&scale,length:MemoryLayout.size(ofValue:scale),index:1)
  encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
  encoder.endEncoding(); buffer.present(drawable); buffer.commit()
 }
}
@MainActor final class FixtureView:NSView {
 let color:NSColor
 init(frame:CGRect,color:NSColor){self.color=color;super.init(frame:frame)}
 required init?(coder:NSCoder){fatalError()}
 override func draw(_ rect:NSRect){
  color.setFill();bounds.fill()
  color.blended(withFraction:0.7,of:.black)!.setFill()
  for x in stride(from:0,to:Int(bounds.width),by:16){NSRect(x:x,y:0,width:8,height:Int(bounds.height)).fill()}
 }
}
@MainActor final class FixtureDelegate:NSObject,NSApplicationDelegate {
 var windows:[NSWindow]=[]
 func applicationDidFinishLaunching(_ note:Notification){
  let screen=NSScreen.screens[0]
  let windowed = ProcessInfo.processInfo.arguments.contains("--windowed")
  for (name,color) in [(Bundle.main.bundleIdentifier!.hasSuffix(".b") ? "Fixture B" : "Fixture A", Bundle.main.bundleIdentifier!.hasSuffix(".b") ? NSColor.magenta : NSColor.green)] {
   let w=NSWindow(contentRect:CGRect(x:screen.frame.minX+100,y:screen.frame.minY+100,width:800,height:600),styleMask:windowed ? [.borderless] : [.titled,.closable,.resizable],backing:.buffered,defer:false)
   if windowed { w.setFrame(screen.frame, display:false) }
   w.isReleasedWhenClosed=false;w.title=name;w.collectionBehavior=[.fullScreenPrimary]
   if ProcessInfo.processInfo.arguments.contains("--metal") {
    do { w.contentView = try MetalFixtureView(frame:w.contentLayoutRect,color:color) }
    catch { fputs("FAIL Metal fixture: \(error)\n",stderr); exit(1) }
   } else { w.contentView=FixtureView(frame:w.contentLayoutRect,color:color) }
   windows.append(w)
  }
  Task { @MainActor in
   for w in windows {w.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);try? await Task.sleep(for:.milliseconds(300));if !windowed { w.toggleFullScreen(nil) };try? await Task.sleep(for:.seconds(2));print("WINDOW",w.title,w.styleMask.contains(.fullScreen));fflush(stdout)}
   print("FIXTURE READY");fflush(stdout)
   try? await Task.sleep(for:.seconds(600));NSApp.terminate(nil)
  }
 }
}
@main struct Fixture {
 @MainActor static func main(){let app=NSApplication.shared;let delegate=FixtureDelegate();app.delegate=delegate;app.setActivationPolicy(.regular);withExtendedLifetime(delegate){app.run()}}
}
