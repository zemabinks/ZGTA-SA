#!/usr/bin/env python3
"""Preferences plus extracted live owner wiring. No UI or real defaults writes."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
OUT = ROOT/'local-only/native-physics/tests/settings'
OUT.mkdir(parents=True,exist_ok=True)
paths = ['ios/App/NativeAppSettings.swift','ios/App/NativeGameCamera.swift','ios/App/ServerAddress.swift',
         'ios/App/NativeWorldRenderer.swift','ios/App/NativeGameViewController.swift',
         'ios/App/NativeOptionsViewController.swift','ios/App/NativePausePanel.swift',
         'smoke_native_settings.swift','smoke_native_settings.py']
inputs = {path:(ROOT/path).read_bytes() for path in paths}
vc = inputs['ios/App/NativeGameViewController.swift'].decode()
renderer = inputs['ios/App/NativeWorldRenderer.swift'].decode()
options = inputs['ios/App/NativeOptionsViewController.swift'].decode()

def extract(source, marker):
    start=source.index(marker); brace=source.index('{',start); depth=1; end=brace+1
    while depth:
        depth += (source[end]=='{')-(source[end]=='}'); end += 1
    return source[start:end].replace('private ','')

render_methods='\n'.join(extract(renderer,marker) for marker in [
    'func applySettings(', 'func updateSettingsViewport()', 'func lookCamera(', 'func cycleCameraView()',
    'var footCameraView:', 'var vehicleCameraView:'])
vc_methods='\n'.join(extract(vc,marker) for marker in ['private func applyAppSettings()', 'private func cycleCameraPreference()'])
onfoot_start=renderer.index('            gameCamera.lookAnalog(x: turn,')
onfoot_end=renderer.index('\n            heading =',onfoot_start)
onfoot=renderer[onfoot_start:onfoot_end]
observer_start=vc.index('        settingsObserver = NotificationCenter.default.addObserver(forName: NativeAppSettings.didChange,')
observer_end=vc.index('\n        applyAppSettings()',observer_start)
observer=vc[observer_start:observer_end]
assert 'renderer?.updateSettingsViewport()' in extract(vc,'override func viewDidLayoutSubviews(')
assert 'applyAppSettings()' in extract(vc,'override func viewDidAppear(')
assert 'appSettings.update' in extract(vc,'@objc private func openPause()')
assert 'panel.onMap' in extract(vc,'@objc private func openPause()')
assert 'panel.onOptions' in extract(vc,'@objc private func openPause()')
assert 'NativeOptionsViewController(settings: appSettings)' in extract(vc,'@objc private func openOptions()')
assert '.overFullScreen' in extract(vc,'@objc private func openOptions()')
for field in ['renderScale','cameraSensitivity','radarSpan','masterVolume','effectsVolume','radioVolume',
              'invertY','radarVisible','radarCircular','radarWorldMarkers','regionalWeather','reduceMenuMotion']:
    assert 'key: \\.'+field in options, 'missing real option key path: '+field
for field in ['frameRate','footView','vehicleView']:
    assert '$0.'+field+' =' in options,'missing real option setter: '+field
assert 'self?.settings.reset()' in options

harness=r'''
import Foundation
import CoreGraphics
struct TestScreen {var scale:CGFloat=3;var maximumFramesPerSecond=60;static var main=TestScreen()}
typealias UIScreen=TestScreen
struct TestWindow {var screen=TestScreen()}
final class TestView {var window:TestWindow?=TestWindow();var bounds=CGRect(x:0,y:0,width:844,height:390)
    var contentScaleFactor:CGFloat=3;var drawableSize=CGSize.zero;var autoResizeDrawable=true;var preferredFramesPerSecond=0}
final class TestCamera {
    var footZoom=2,vehicleView=2;var heading:Float=0,pitch:Float=0
    var lastLook:(Float,Bool,Bool)?
    func setFootZoom(_ value:Int){footZoom=value}
    func setVehicleView(_ value:Int){vehicleView=value}
    func cycleFootZoom(){footZoom=footZoom%3+1}
    func cycleVehicleView(){vehicleView=vehicleView%6+1}
    func lookAnalog(x:Float,y:Float,delta:Float,driving:Bool=false,sensitivity:Float=1,inverted:Bool=false){lastLook=(sensitivity,inverted,driving)}
}
final class RendererSettingsHarness {
    let view=TestView(),gameCamera=TestCamera()
    var appPreferences=NativeAppSettings.defaults,weatherAuto=false,driving=false
    var heading:Float=0,cameraPitch:Float=0
'''+render_methods+'''
    func actualFootLook(turn:Float,lookVertical:Float,delta:Float) {
'''+onfoot+'''
    }
}
final class TestRadar {var isHidden=false,circular=true,showWorldMarkers=true;var span:CGFloat=400}
final class TestHUD {let radar=TestRadar()}
final class TestButton {var isHidden=false}
struct CAFrameRateRange {var minimum:Float=0,maximum:Float=0,preferred:Float=0}
final class TestLink {var preferredFrameRateRange=CAFrameRateRange()}
final class TestAudio {
    var radio=false;var gain:Float=0
    func applySettings(_ s:NativeAppSettings.Snapshot){gain=radio ? s.effectiveRadioGain:s.effectiveEffectsGain}
}
final class VCSettingsHarness {
    let view=TestView(),gameHUD=TestHUD(),mapButton=TestButton(),audio=TestAudio(),radio=TestAudio()
    var isViewLoaded=true,renderer:RendererSettingsHarness?=RendererSettingsHarness(),displayLink:TestLink?=TestLink()
    let appSettings:NativeAppSettings
    var settingsObserver:NSObjectProtocol?
    init(_ settings:NativeAppSettings){appSettings=settings;radio.radio=true}
    deinit {if let settingsObserver {NotificationCenter.default.removeObserver(settingsObserver)}}
    func observe() {
'''+observer+'''
    }
'''+vc_methods+'''
    func apply(){applyAppSettings()}
    func cycle(){cycleCameraPreference()}
}
func verifyNativeSettingsOwnerIntegration() {
    let memory=SettingsMemory(),store=NativeAppSettings(storage:memory),vc=VCSettingsHarness(store)
    vc.observe();vc.apply()
    settingsCheck(vc.renderer!.view.drawableSize==CGSize(width:2532,height:1170),"default real owner resolution")
    settingsCheck(!vc.renderer!.view.autoResizeDrawable,"manual drawable size survives later layouts")
    settingsCheck(vc.displayLink!.preferredFrameRateRange.maximum==60 && vc.renderer!.view.preferredFramesPerSecond==60,"both default clocks60")
    settingsClose(Double(vc.audio.gain),0.7,"initial effects apply")
    settingsClose(Double(vc.radio.gain),0.6,"initial radio apply")
    vc.view.window=TestWindow(screen:TestScreen(scale:3,maximumFramesPerSecond:120))
    store.update {
        $0.frameRate=120;$0.renderScale=0.5;$0.cameraSensitivity=2.25;$0.invertY=true
        $0.footView=3;$0.vehicleView=6;$0.regionalWeather=true
        $0.radarVisible=false;$0.radarCircular=false;$0.radarSpan=900;$0.radarWorldMarkers=false
        $0.masterVolume=0
    }
    let renderer=vc.renderer!
    settingsCheck(renderer.view.drawableSize==CGSize(width:1266,height:585),"live scale changes actual drawable owner")
    settingsCheck(vc.displayLink!.preferredFrameRateRange.maximum==120 && renderer.view.preferredFramesPerSecond==120,"live coordinated120 cap")
    settingsCheck(vc.displayLink!.preferredFrameRateRange.minimum==30 && vc.displayLink!.preferredFrameRateRange.preferred==120,"adaptive range has requested preference")
    settingsCheck(renderer.gameCamera.footZoom==3 && renderer.gameCamera.vehicleView==6,"both view setters applied")
    settingsCheck(renderer.weatherAuto,"weather model applied")
    settingsCheck(vc.gameHUD.radar.isHidden && vc.mapButton.isHidden,"hidden radar has no invisible map hitbox")
    settingsCheck(!vc.gameHUD.radar.circular && !vc.gameHUD.radar.showWorldMarkers && vc.gameHUD.radar.span==900,"radar options applied")
    settingsCheck(vc.audio.gain==0 && vc.radio.gain==0,"master reaches both audio owners")
    renderer.actualFootLook(turn:0.2,lookVertical:0.4,delta:1/60)
    settingsCheck(renderer.gameCamera.lastLook!.0==2.25 && renderer.gameCamera.lastLook!.1,"actual on-foot call carries sensitivity/invert")
    renderer.driving=true;renderer.lookCamera(x:0.2,y:0.4,delta:1/60)
    settingsCheck(renderer.gameCamera.lastLook!.0==2.25 && renderer.gameCamera.lastLook!.1 && renderer.gameCamera.lastLook!.2,"actual driving camera call carries preferences")
    vc.cycle()
    settingsCheck(store.snapshot.vehicleView==1 && renderer.gameCamera.vehicleView==1,"existing camera cycle saves new model")
    renderer.driving=false;vc.cycle()
    settingsCheck(store.snapshot.footView==1,"foot cycle saves new model")
    vc.view.window=TestWindow(screen:TestScreen(scale:2,maximumFramesPerSecond:60));vc.apply()
    settingsCheck(vc.displayLink!.preferredFrameRateRange.maximum==60 && renderer.view.preferredFramesPerSecond==60,"both caps follow60Hz screen")
    renderer.view.bounds=CGRect(x:0,y:0,width:1024,height:768);renderer.updateSettingsViewport()
    settingsCheck(renderer.view.drawableSize==CGSize(width:1536,height:1152),"layout recalculates scale from new bounds")
    renderer.updateSettingsViewport()
    settingsCheck(renderer.view.drawableSize==CGSize(width:1536,height:1152),"layout reapply never compounds scale")
    let before=renderer.view.drawableSize;renderer.view.bounds = .zero;renderer.updateSettingsViewport()
    settingsCheck(renderer.view.drawableSize==before,"transient zero bounds do not request zero drawable")
    renderer.view.bounds=CGRect(x:0,y:0,width:844,height:390)
    store.reset()
    settingsCheck(renderer.view.drawableSize==CGSize(width:2532,height:1170),"reset changes live drawable")
    settingsCheck(renderer.gameCamera.footZoom==2 && renderer.gameCamera.vehicleView==2 && !renderer.weatherAuto,"reset camera/weather")
    settingsCheck(!vc.gameHUD.radar.isHidden && !vc.mapButton.isHidden && vc.gameHUD.radar.circular && vc.gameHUD.radar.span==400,"reset live radar")
    settingsClose(Double(vc.audio.gain),0.7,"reset effects")
    settingsClose(Double(vc.radio.gain),0.6,"reset radio")
    let other=NativeAppSettings(storage:SettingsMemory())
    other.update {$0.renderScale=0.5}
    settingsCheck(renderer.view.drawableSize==CGSize(width:2532,height:1170),"unrelated store notification ignored")
    vc.isViewLoaded=false;store.update {$0.renderScale=0.5}
    settingsCheck(renderer.view.drawableSize==CGSize(width:2532,height:1170),"unloaded owner not mutated")
    vc.isViewLoaded=true;vc.apply()
    settingsCheck(renderer.view.drawableSize==CGSize(width:1266,height:585),"returning owner receives current snapshot")
}
'''

with tempfile.TemporaryDirectory(prefix='zgtasa-settings-') as tmp_name:
    tmp=Path(tmp_name)
    sources=[]
    for path in ['ios/App/NativeAppSettings.swift','ios/App/NativeGameCamera.swift','ios/App/ServerAddress.swift','smoke_native_settings.swift']:
        target=tmp/Path(path).name;target.write_bytes(inputs[path]);sources.append(str(target))
    generated=tmp/'SettingsOwnerIntegration.swift';generated.write_text(harness);sources.append(str(generated))
    command=['xcrun','swiftc','-O','-module-cache-path',str(OUT/'module-cache'),*sources,'-o',str(tmp/'verify')]
    subprocess.run(command,check=True)
    result=subprocess.run([str(tmp/'verify')],capture_output=True,text=True,check=True)
    print(result.stdout.strip())
    report=dict(status='PASS',output=result.stdout.strip(),
                coverage=['validated/default/partial/corrupt/legacy persistence','live notification/reset and audio gain contract',
                          'actual extracted Renderer/VC settings owner methods','actual camera at30/60/120Hz sensitivity/invert',
                          'drawable scale/layout/zero viewport','coordinated display caps/hardware maximum'],
                limits=['Native UIKit/Metal construction and physical frame rates require app/device acceptance',
                        'Audio waveform/live voices are verified by the independent audio test'],
                sourceHashes={path:hashlib.sha256(data).hexdigest() for path,data in inputs.items()},
                liveFilesStillMatchSnapshot={path:(ROOT/path).read_bytes()==data for path,data in inputs.items()})
    (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
