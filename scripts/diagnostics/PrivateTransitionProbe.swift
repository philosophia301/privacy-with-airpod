import AppKit
import ScreenCaptureKit
import CoreMedia
import Foundation

private struct GridFrame: Encodable {
 let schema = 1
 let stream: String
 let tick: UInt64
 let width: Int
 let height: Int
 let cols = GridMetrics.columns
 let rows = GridMetrics.rows
 let energy: [Double]
 let regions: [UInt8]
 let samples: [Int]
}

final class MeasureOutput:NSObject,SCStreamOutput,@unchecked Sendable {
 let label:String
 let grid: Bool
 private static let outputLock = NSLock()
 init(_ label:String, grid: Bool = false){self.label=label;self.grid=grid}
 private func writeData(_ data: Data) {
  Self.outputLock.lock(); defer { Self.outputLock.unlock() }
  FileHandle.standardOutput.write(data)
 }
 private func writeLine(_ line: String) {
  var data = Data(line.utf8)
  data.append(0x0a)
  writeData(data)
 }
 private func writeGrid(_ tick: UInt64, _ buffer: CVPixelBuffer) {
  let width = CVPixelBufferGetWidth(buffer)
  let height = CVPixelBufferGetHeight(buffer)
  let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
  CVPixelBufferLockBaseAddress(buffer,.readOnly); defer { CVPixelBufferUnlockBaseAddress(buffer,.readOnly) }
  guard let pointer = CVPixelBufferGetBaseAddress(buffer) else {
   writeLine("GRID ERROR \(label) \(tick) missing-base-address")
   return
  }
  let byteCount = rowBytes > 0 && height <= Int.max / rowBytes ? rowBytes * height : 0
  let bytes = UnsafeRawBufferPointer(start: pointer, count: byteCount)
  guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
        let metrics = GridMetrics.measure(bytes: bytes, width: width, height: height, rowBytes: rowBytes) else {
   writeLine("GRID ERROR \(label) \(tick) invalid-bgra-buffer")
   return
  }
  let frame = GridFrame(stream: label, tick: tick, width: width, height: height,
                        energy: metrics.energy, regions: metrics.regions, samples: metrics.samples)
  do {
   var data = try JSONEncoder().encode(frame)
   data.append(0x0a)
   // One write keeps each JSONL frame together even though raw and shown
   // callbacks are delivered on separate queues.
   writeData(data)
  } catch {
   writeLine("GRID ERROR \(label) \(tick) json-encoding-failed")
  }
 }
 func stream(_ stream:SCStream,didOutputSampleBuffer sample:CMSampleBuffer,of type:SCStreamOutputType){
  guard type == .screen else {
   if grid { writeLine("GRID ERROR \(label) unexpected-stream-type") }
   return
  }
  let meta=CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:false) as? [[SCStreamFrameInfo:Any]]
  if grid {
   guard let attachment = meta?.first else { writeLine("GRID ERROR \(label) missing-attachments"); return }
   guard let t = attachment[.displayTime] as? UInt64 else { writeLine("GRID ERROR \(label) missing-display-time"); return }
   guard let status = attachment[.status] as? Int else { writeLine("GRID ERROR \(label) missing-status \(t)"); return }
   guard status == 0 else { writeLine("GRID STATUS \(label) \(t) \(status)"); return }
   guard let b = sample.imageBuffer else { writeLine("GRID ERROR \(label) missing-image-buffer"); return }
   writeGrid(t, b)
   return
  }
  guard let b = sample.imageBuffer else { return }
  guard let t=meta?.first?[.displayTime] as? UInt64,meta?.first?[.status] as? Int == 0 else{return}
  CVPixelBufferLockBaseAddress(b,.readOnly);defer{CVPixelBufferUnlockBaseAddress(b,.readOnly)}
  guard let ptr=CVPixelBufferGetBaseAddress(b) else{return}
  let w=CVPixelBufferGetWidth(b),h=CVPixelBufferGetHeight(b),stride=CVPixelBufferGetBytesPerRow(b)
  var green=0,magenta=0;var energy=0.0;var edge = 0.0
  var blueCount=0;var blueX=0.0
  var profile=[Double](repeating:0,count:16)
  var regions=[Int](repeating:0,count:16)
  for y in 0..<h {
  let row=ptr.advanced(by:stride*y).assumingMemoryBound(to:UInt8.self)
  for x in 0..<w {let d=Double(row[x*4+1])-(Double(row[x*4])+Double(row[x*4+2]))/2;energy+=d;if d>25{green+=1};if d < -25{magenta+=1};regions[min(15,x*16/w)] |= d>25 ? 1 : d < -25 ? 2 : 4}
  for x in 0..<w where row[x*4] > 150 && row[x*4+1] < 10 && row[x*4+2] < 10 { blueCount += 1; blueX += Double(x) }
  for x in 1..<w {
   let a = Double(row[x*4+1])-(Double(row[x*4])+Double(row[x*4+2]))/2
   let b = Double(row[(x-1)*4+1])-(Double(row[(x-1)*4])+Double(row[(x-1)*4+2]))/2
   edge += abs(a-b)
   profile[min(15,x*16/w)] += abs(a-b)
  }
  }
  print("REGIONS",label,t,regions.map(String.init).joined(separator:","))
  print("PROFILE",label,t,profile.map { String($0/Double(h)*16/432) }.joined(separator:","))
  if blueCount > 0 { print("MARKER",label,t,blueX/Double(blueCount)/Double(w)) }
  print("DETAIL",label,t,edge/Double((w-1)*h)*Double(w)/432)
  print("MEASURE",label,t,mach_absolute_time(),Double(green)/Double(w*h),Double(magenta)/Double(w*h),energy/Double(w*h))
 }
}
@main struct Probe {
 @MainActor static func main(){NSApplication.shared.setActivationPolicy(.accessory);Task{@MainActor in do{try await run()}catch{print("FAIL",error);exit(1)};exit(0)};NSApplication.shared.run()}
 @MainActor static func run() async throws {
  let mode=try String(contentsOfFile:"/tmp/privacy-private-measure-mode",encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)
  let known = ["off","plain","host","tag23","tag16","unflattened","moving","native","nativebase","window","highwindow","highvariable","nojoin","nofull","sticky","tag20","maximum","overscan","marker","partial","compensated","weakoverscan","periodic","dynamic","fixedangle","continuous","labobserver","faultpulse","highoverscan","wideoverscan","stickyoverscan","flatoverscan","nojoinoverscan","immovable","tiled","weaktiled","prepared","preparedtiles","preallocatedtiles","unclippedtiles","mesh","preparedmesh","menutag","statusbartag","broadtiles","broadunclippedtiles","rebasedoverscan","clipoverscan","independent"]
  let firstDisplayOnly = ProcessInfo.processInfo.arguments.contains("--first-display")
  let builtInOnly = ProcessInfo.processInfo.arguments.contains("--built-in-only")
  let grid = ProcessInfo.processInfo.arguments.contains("--grid")
  guard !(builtInOnly && firstDisplayOnly) else {
   throw NSError(domain:"PrivacyBackdropProbe",code:5,userInfo:[NSLocalizedDescriptionKey:"--built-in-only cannot be combined with --first-display"])
  }
  guard known.contains(mode), !NSScreen.screens.isEmpty, (NSScreen.screens.count == 1 || firstDisplayOnly || builtInOnly) else {
   throw NSError(domain:"PrivacyBackdropProbe",code:2,userInfo:[NSLocalizedDescriptionKey:"Known mode and exactly one screen required by this diagnostic"])
  }
  let screen: NSScreen
  if builtInOnly {
   guard let builtIn = NSScreen.screens.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) else {
   throw NSError(domain:"PrivacyBackdropProbe",code:6,userInfo:[NSLocalizedDescriptionKey:"--built-in-only requires an available built-in display"])
   }
   screen = builtIn
   // Keep the target marker in an existing diagnostic record class so grid
   // log consumers can ignore it while still requiring the literal marker.
   print("DISPLAY MARKER framewithinbuiltin", screen.displayID)
  } else {
   screen = NSScreen.screens[0]
  }
  let marker=NSWindow(contentRect:CGRect(x:0,y:0,width:50,height:50),styleMask:.borderless,backing:.buffered,defer:false);marker.isReleasedWhenClosed=false;marker.collectionBehavior=[.canJoinAllSpaces,.canJoinAllApplications,.fullScreenAuxiliary,.stationary];marker.level=NSWindow.Level(rawValue:26);marker.orderFrontRegardless();defer{marker.close()}
  try await Task.sleep(for:.milliseconds(500))
  let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:false)
  let own=content.applications.filter{$0.processID==getpid()};guard !own.isEmpty else{throw NSError(domain:"PrivacyBackdropProbe",code:3,userInfo:[NSLocalizedDescriptionKey:"Own capture application missing"])}
  let lab=content.applications.filter{$0.bundleIdentifier == "local.privacy-with-airpod.blurlab"}
  if mode == "labobserver", lab.isEmpty { throw NSError(domain:"PrivacyBackdropProbe",code:4,userInfo:[NSLocalizedDescriptionKey:"Blur Lab required for observer mode"]) }
  let display=content.displays.first{$0.displayID==screen.displayID}!
  let raw=SCContentFilter(display:display,excludingApplications:own + (mode == "labobserver" ? lab : []),exceptingWindows:[])
  let visible=SCContentFilter(display:display,excludingWindows:[])
  let nativeWidth = Int((screen.frame.width * screen.backingScaleFactor).rounded())
  let nativeHeight = Int((screen.frame.height * screen.backingScaleFactor).rounded())
  guard nativeWidth > 0, nativeHeight > 0 else {
   throw NSError(domain:"PrivacyBackdropProbe",code:7,userInfo:[NSLocalizedDescriptionKey:"Selected display has no pixel dimensions"])
  }
  let cfg=SCStreamConfiguration()
  if grid {
   // Full display in display points, with the stream at the display's native
   // backing-pixel dimensions. Aspect preservation is disabled only because
   // sourceRect and output dimensions are the same display geometry.
   cfg.width=nativeWidth;cfg.height=nativeHeight;cfg.sourceRect=CGRect(origin:.zero,size:screen.frame.size)
  } else {
   cfg.width=Int(screen.frame.width * screen.backingScaleFactor);cfg.height=Int(8 * screen.backingScaleFactor);cfg.sourceRect=CGRect(x:0,y:screen.frame.height/2,width:screen.frame.width,height:8)
  }
  cfg.preservesAspectRatio=false;cfg.pixelFormat=kCVPixelFormatType_32BGRA;cfg.minimumFrameInterval=CMTime(value:1,timescale:60);cfg.queueDepth=3;cfg.showsCursor=false
  if grid { print("GRID CONFIG", nativeWidth, nativeHeight, cfg.sourceRect, "sampled-stride", 4) }
  var streams:[SCStream]=[];var outputs:[MeasureOutput]=[]
  do {
   for(label,filter) in [("raw",raw),("shown",visible)]{let o=MeasureOutput(label,grid:grid);outputs.append(o);let s=SCStream(filter:filter,configuration:cfg,delegate:nil);streams.append(s);try s.addStreamOutput(o,type:.screen,sampleHandlerQueue:DispatchQueue(label:label));try await s.startCapture()}
  } catch {
   for stream in streams { try? await stream.stopCapture() }
   throw error
  }
  let privateCover = PrivateCover()
  do {

  print("POLICY", NSApp.activationPolicy().rawValue)
  let targetScreens = firstDisplayOnly || builtInOnly ? [screen] : NSScreen.screens
  print("DISPLAY", screen.displayID, screen.frame, screen.backingScaleFactor)
  let settings=Dictionary(uniqueKeysWithValues:targetScreens.map{($0.displayID,RenderSettings(radius:(mode=="weakoverscan" || mode=="weaktiled") ? 3 : 31.25,forceCovered:true))})
  PBSetDiagnosticBackdropFlags(mode=="clipoverscan" ? 8 : mode=="prepared" || mode=="preparedtiles" || mode=="preparedmesh" ? 3 : mode=="preallocatedtiles" ? 2 : mode=="unclippedtiles" || mode=="broadunclippedtiles" ? 1 : 0)
  if mode != "off" && mode != "labobserver" {
   do {
    try await privateCover.start(settings:settings, host:mode != "plain", independent:mode=="independent" || ProcessInfo.processInfo.arguments.contains("--independent"), swipeBits:mode=="menutag" ? (1 << 14) : mode=="statusbartag" ? (1 << 15) : mode=="stickyoverscan" ? (1 << 13) | (1 << 20) : mode=="flatoverscan" ? (1 << 20) : (mode=="tag23" || mode=="unflattened" || mode=="moving") ? (1 << 23) : mode=="tag16" ? (1 << 16) : mode=="sticky" ? (1 << 13) : mode=="tag20" ? (1 << 20) : 0, unflattened:mode=="unflattened" || mode=="moving", stationary:mode != "moving", native:mode=="native" || mode=="nativebase", nativeBaseline:mode=="nativebase", windowBlur:mode=="window" || mode=="highwindow", level:mode=="maximum" ? Int(CGWindowLevelForKey(.maximumWindow)) : mode.hasPrefix("high") ? 1000 : 25, joining:(mode=="nojoin" || mode=="nojoinoverscan") ? 1 : mode=="nofull" ? 2 : 0, overscan:["overscan","marker","partial","compensated","weakoverscan","periodic","dynamic","fixedangle","continuous","faultpulse","highoverscan","wideoverscan","stickyoverscan","flatoverscan","nojoinoverscan","immovable","tiled","weaktiled","prepared","preparedtiles","preallocatedtiles","unclippedtiles","rebasedoverscan","clipoverscan"].contains(mode), overscanScreens:mode=="wideoverscan" ? 3 : 1, tiled:mode=="tiled" || mode=="weaktiled" || mode.hasSuffix("tiles"), broadTiles:mode.hasPrefix("broad"), immovable:mode=="immovable", pinnedMesh:mode.hasSuffix("mesh"), rebase:mode=="rebasedoverscan" || ProcessInfo.processInfo.arguments.contains("--rebase"), marker:mode=="marker", partial:["partial","compensated","periodic"].contains(mode), compensate:["compensated","periodic","dynamic","fixedangle","continuous"].contains(mode), periodic:["periodic","dynamic","fixedangle","continuous"].contains(mode))
   } catch {
    for stream in streams { try? await stream.stopCapture() }
    throw error
   }
  }
  try await Task.sleep(for:.milliseconds(500))
  let check = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:false)
  for w in check.windows where w.owningApplication?.processID == getpid() {print("WINDOW",w.windowID,w.isOnScreen,w.windowLayer,w.frame)}
  var timebase = mach_timebase_info_data_t(); mach_timebase_info(&timebase)
  print("CLOCK",timebase.numer,timebase.denom)
  print("MEASURE READY",mode,mach_absolute_time());fflush(stdout)
  let inputs = Task { @MainActor () -> Error? in
   guard ["dynamic","fixedangle","continuous"].contains(mode) else { return nil }
   do {
    let count = mode == "continuous" ? 1600 : 16
    for index in 0..<count {
     let angle = mode == "dynamic" ? (index % 2 == 0 ? 45.0 : -45.0) : 45 + (mode == "continuous" ? sin(Double(index) / 20) : 0)
     try privateCover.update(settings:[screen.displayID:RenderSettings(angle:angle,start:35,full:55,radius:20)])
     if mode == "dynamic" { print("TARGET",mach_absolute_time(),angle) }
     try await Task.sleep(for:.milliseconds(mode == "continuous" ? 8 : 1000))
    }
   } catch is CancellationError {} catch { return error }
   return nil
  }
  let fault = Task { @MainActor () -> Error? in
   guard mode == "faultpulse" else { return nil }
   defer { privateCover.setDiagnosticHidden(false) }
   do {
    try await Task.sleep(for:.seconds(4))
    print("FAULT BEGIN",mach_absolute_time()); privateCover.setDiagnosticHidden(true)
    try await Task.sleep(for:.milliseconds(200))
    privateCover.setDiagnosticHidden(false); print("FAULT END",mach_absolute_time())
   } catch is CancellationError {} catch { return error }
   return nil
  }
  let trace = Task { @MainActor () -> Error? in
   do { while !Task.isCancelled { try privateCover.trace(); try await Task.sleep(for:.milliseconds(8)) } }
   catch is CancellationError {} catch { return error }
   return nil
  }
  try await Task.sleep(for:.seconds(ProcessInfo.processInfo.arguments.contains("--manual-hold") ? 120 : 16))
  trace.cancel()
  let traceFailure = await trace.value
  inputs.cancel()
  let inputFailure = await inputs.value
  fault.cancel()
  let faultFailure = await fault.value
  privateCover.stop()
  for s in streams{try await s.stopCapture()}
  withExtendedLifetime(outputs){}
  if let traceFailure { throw traceFailure }
  if let inputFailure { throw inputFailure }
  if let faultFailure { throw faultFailure }
  print("MEASURE DONE",mode)
  } catch {
   // Cover setup or any pre-READY failure must not leave capture streams
   // running while the process reports startup failure.
   privateCover.stop()
   for stream in streams { try? await stream.stopCapture() }
   throw error
  }
 }
}
