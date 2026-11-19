import UIKit

// UIKit carrier only. Controller geometry and safe-area insets are synthetic;
// the generated methods/constraints and icon-button class come from App source.
final class ProbeRootView:UIView {
    let syntheticSafeArea=UILayoutGuide()
    init(size:CGSize,insets:UIEdgeInsets){
        super.init(frame:CGRect(origin:.zero,size:size));addLayoutGuide(syntheticSafeArea)
        NSLayoutConstraint.activate([
            syntheticSafeArea.leadingAnchor.constraint(equalTo:leadingAnchor,constant:insets.left),
            syntheticSafeArea.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-insets.right),
            syntheticSafeArea.topAnchor.constraint(equalTo:topAnchor,constant:insets.top),
            syntheticSafeArea.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-insets.bottom)])
    }
    required init?(coder:NSCoder){fatalError("Not used")}
}
extension UIView {var fixtureSafeAreaLayoutGuide:UILayoutGuide{(self as! ProbeRootView).syntheticSafeArea}}
final class ProbeHUD:UIView {
    let radar=UIView()
    var syntheticWindowSize=CGSize.zero
    override init(frame:CGRect){super.init(frame:frame);isUserInteractionEnabled=false;addSubview(radar)}
    required init?(coder:NSCoder){fatalError("Not used")}
    override func layoutSubviews(){
        super.layoutSubviews()
        let windowSize=syntheticWindowSize // Synthetic size, not a claimed physical window.
        // RADAR_LAYOUT
    }
    func updateWeapon(id:Int,name:String,magazine:Int,reserve:Int){}
    func loadWeaponIcon(server:ProbeServer,weapon:Int){}
}
struct ProbeServer{}
struct ProbeVehicle {var id="fixture"}
struct ProbeWeapon {var name="Fixture",capacity=17,supportsAttack=true}
final class ProbeWeapons {var current=ProbeWeapon(),selected=22,reloading=false}
final class ProbeNetwork {var health=100}
final class ProbeRenderer {
    var isPassenger=false
    var vehicleKind="car",hasVehicleWorkingControls=false,hasJetNozzle=false,vehicleWorkingIsTow=false
    var canUnhitchVehicle=false,hasLandingGear=false,hasVehicleHorn=false,isChuting=false
    var canNativeFootMeleeGuard=false,supportsFootWeaponAim=true
    var vehicleWorkingControl:Float=0,vehicleJetControl:Float=0
}
struct ProbeMode {
    var name:String,kind:String?=nil,working=false,tow=false,nozzle=false,unhitch=false,gear=false,horn=false
    var pistol=true,melee=false,guarding=false,attack=true,deploy=false,dead=false,passenger=false
}
struct ProbeGeometry {let name:String,size:CGSize,insets:UIEdgeInsets}
let probeModes:[ProbeMode]=[
    .init(name:"foot-pistol"),.init(name:"foot-melee",pistol:false,melee:true,guarding:true),
    .init(name:"foot-utility",pistol:false,attack:false),.init(name:"foot-dead",dead:true),
    .init(name:"foot-parachute",deploy:true),.init(name:"car",kind:"car",horn:true),
    .init(name:"car-unhitch",kind:"car",unhitch:true,horn:true),.init(name:"motorcycle",kind:"bike",horn:true),
    .init(name:"bicycle",kind:"bicycle"),.init(name:"boat",kind:"boat",horn:true),
    .init(name:"plane",kind:"plane",gear:true),.init(name:"helicopter",kind:"helicopter",gear:true),
    .init(name:"passenger-car",kind:"car",passenger:true),.init(name:"passenger-bike",kind:"bike",passenger:true),
    .init(name:"train",kind:"train",horn:true),.init(name:"working",kind:"car",working:true,horn:true),
    .init(name:"tow-unhitch",kind:"car",working:true,tow:true,unhitch:true,horn:true),
    .init(name:"vtol",kind:"plane",nozzle:true,gear:true)]
let probeGeometries:[ProbeGeometry]=[
    .init(name:"568x320",size:.init(width:568,height:320),insets:.zero),
    .init(name:"667x375",size:.init(width:667,height:375),insets:.zero),
    .init(name:"812x375-cutout",size:.init(width:812,height:375),insets:.init(top:0,left:44,bottom:21,right:44)),
    .init(name:"844x390-cutout",size:.init(width:844,height:390),insets:.init(top:0,left:47,bottom:21,right:47)),
    .init(name:"852x393-cutout",size:.init(width:852,height:393),insets:.init(top:0,left:59,bottom:21,right:59)),
    .init(name:"896x414-cutout",size:.init(width:896,height:414),insets:.init(top:0,left:44,bottom:21,right:44)),
    .init(name:"1024x768-tablet",size:.init(width:1024,height:768),insets:.init(top:24,left:0,bottom:20,right:0)),
    .init(name:"1194x834-tablet",size:.init(width:1194,height:834),insets:.init(top:24,left:0,bottom:20,right:0)),
    .init(name:"1366x1024-tablet",size:.init(width:1366,height:1024),insets:.init(top:24,left:0,bottom:20,right:0))]
protocol ProbeController:AnyObject {
    var view:UIView! {get set}
    var namedButtons:[(String,UIButton)]{get}
    var recordedActions:[String]{get set}
    var acceptsHeldInput:Bool{get set}
    var handbrakeIsHeld:Bool{get}
    var brakeIsHeld:Bool{get}
    func prepare(_ mode:ProbeMode,_ geometry:ProbeGeometry)
}
// CONTROLLERS

func owner(_ hit:UIView?)->UIButton?{
    var item=hit
    while let current=item {if let button=current as? UIButton{return button};item=current.superview}
    return nil
}
func runMatrix(make:()->ProbeController)->[String:Any]{
    var checks=0,failures:[[String:Any]]=[],cases:[[String:Any]]=[]
    func check(_ ok:Bool,_ message:String,_ mode:String,_ geometry:String,_ details:[String:Any]=[:]){
        checks+=1;if !ok {failures.append(["message":message,"mode":mode,"geometry":geometry,"details":details])}
    }
    for geometry in probeGeometries {for mode in probeModes {
        let controller=make();controller.prepare(mode,geometry)
        let named=controller.namedButtons
        let visible=named.filter{!$0.1.isHidden && $0.1.alpha>0.01 && $0.1.isUserInteractionEnabled}
        let lookup=Dictionary(uniqueKeysWithValues:named.map{(ObjectIdentifier($0.1),$0.0)})
        var boxes:[String:[Double]]=[:]
        for(name,button)in visible {
            let rect=button.convert(button.bounds,to:controller.view)
            boxes[name]=[rect.origin.x,rect.origin.y,rect.width,rect.height].map(Double.init)
            check(rect.width>=42 && rect.height>=42,"Visible control lost its touch area",mode.name,geometry.name,["control":name,"frame":boxes[name]!])
            check(controller.view.bounds.insetBy(dx:-0.01,dy:-0.01).contains(rect),"Visible control outside root bounds",mode.name,geometry.name,["control":name])
            for (dx,dy) in [(0.5,0.5),(0.25,0.5),(0.75,0.5),(0.5,0.25),(0.5,0.75)] {
                let point=CGPoint(x:rect.minX+rect.width*dx,y:rect.minY+rect.height*dy)
                let hit=owner(controller.view.hitTest(point,with:nil))
                check(hit===button,"Visible control lost hitTest ownership",mode.name,geometry.name,["control":name,"hit":hit.flatMap{lookup[ObjectIdentifier($0)]} ?? "non-button","point":[Double(point.x),Double(point.y)]])
            }
        }
        for i in visible.indices {for j in visible.indices where j>i {
            let a=visible[i],b=visible[j],overlap=a.1.convert(a.1.bounds,to:controller.view).intersection(b.1.convert(b.1.bounds,to:controller.view))
            check(overlap.isNull || overlap.width*overlap.height<0.01,"Visible controls overlap",mode.name,geometry.name,["first":a.0,"second":b.0])
        }}
        let byName=Dictionary(uniqueKeysWithValues:named)
        let aboard=mode.kind != nil,driving=aboard && !mode.passenger,road=driving && !["plane","helicopter","boat","train"].contains(mode.kind!)
        if let handbrake=byName["handbrakeButton"] {
            check(handbrake.isHidden == !road,"Handbrake visibility disagrees with road context",mode.name,geometry.name)
            if road {
                check(handbrake.bounds.width>=44 && handbrake.bounds.height>=44,"Handbrake lost 44pt touch area",mode.name,geometry.name)
                for release:UIControl.Event in [.touchUpInside,.touchUpOutside,.touchCancel] {
                    handbrake.sendActions(for:.touchDown)
                    check(controller.handbrakeIsHeld,"Handbrake touch-down did not hold",mode.name,geometry.name)
                    handbrake.sendActions(for:release)
                    check(!controller.handbrakeIsHeld,"Handbrake release/cancel retained held input",mode.name,geometry.name)
                }
                controller.acceptsHeldInput=false;handbrake.sendActions(for:.touchDown)
                check(!controller.handbrakeIsHeld,"Covered input accepted handbrake press",mode.name,geometry.name)
                handbrake.sendActions(for:.touchCancel);controller.acceptsHeldInput=true
                do {
                }
            }
        }
        check(byName["jumpButton"]!.isHidden==aboard,"Driving reused visible Jump control",mode.name,geometry.name)
        check(byName["brakeButton"]!.isHidden == !driving,"Brake visibility disagrees with driving",mode.name,geometry.name)
        if driving {
            for release:UIControl.Event in [.touchUpInside,.touchUpOutside,.touchCancel] {
                byName["brakeButton"]!.sendActions(for:.touchDown)
                check(controller.brakeIsHeld,"Brake touch-down did not hold",mode.name,geometry.name)
                byName["brakeButton"]!.sendActions(for:release)
                check(!controller.brakeIsHeld,"Brake release/cancel retained held input",mode.name,geometry.name)
            }
            controller.acceptsHeldInput=false;byName["brakeButton"]!.sendActions(for:.touchDown)
            check(!controller.brakeIsHeld,"Covered input accepted brake press",mode.name,geometry.name)
            byName["brakeButton"]!.sendActions(for:.touchCancel);controller.acceptsHeldInput=true
            if mode.working || mode.nozzle {check(!byName["weaponButton"]!.isHidden && !byName["reloadButton"]!.isHidden,"Working/nozzle controls missing",mode.name,geometry.name)}
            if mode.unhitch {check(!byName["crouchButton"]!.isHidden,"Confirmed unhitch control missing",mode.name,geometry.name)}
        }
        cases.append(["mode":mode.name,"geometry":geometry.name,"visible":visible.map{$0.0},"frames":boxes])
    }}
    return ["checks":checks,"cases":cases,"failures":failures]
}
final class TouchLayoutDelegate:NSObject,UIApplicationDelegate {
    var window:UIWindow?
    func application(_ application:UIApplication,didFinishLaunchingWithOptions launchOptions:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool{
        let window=UIWindow(frame:UIScreen.main.bounds);window.rootViewController=UIViewController();window.makeKeyAndVisible();self.window=window
        DispatchQueue.main.async {self.run()};return true
    }
    func run(){
        let current=runMatrix{CurrentLayoutController()}
        let historical=runMatrix{HistoricalLayoutController()}
        let failures=current["failures"] as! [[String:Any]]
        let historicalFailures=historical["failures"] as! [[String:Any]]
        let reproduced=historicalFailures.filter{($0["message"] as? String)=="Visible control lost hitTest ownership" && (($0["details"] as? [String:Any])?["control"] as? String)=="jumpButton" && (($0["details"] as? [String:Any])?["hit"] as? String)=="brakeButton"}
        var report:[String:Any]=["status":failures.isEmpty && !reproduced.isEmpty ? "PASS":"FAIL","current":current,"historical":historical,"historicalOverlapHits":reproduced.count,"metadata":probeMetadata,
            "limits":["Real UIKit Auto Layout, button events and UIView.hitTest in a synthetic asset-free controller carrier","Production installHUD/visibility methods are extracted; synthetic safe-area guide replaces only view.safeAreaLayoutGuide","No rendered game, full game controller, real touch delivery, simultaneous UITouch stream, physical device or retail-runtime claim"]]
        let directory=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        let path=directory.appendingPathComponent("touch-layout-report.json")
        report["reportPath"]=path.path
        do {let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]);try data.write(to:path,options:.atomic)}catch{print("TOUCH_LAYOUT_REPORT_ERROR \(error)");exit(2)}
        print("TOUCH_LAYOUT_RESULT \(report["status"]!) currentChecks=\(current["checks"]!) currentFailures=\(failures.count) historicalOverlapHits=\(reproduced.count) path=\(path.path)")
        exit(failures.isEmpty && !reproduced.isEmpty ? 0:1)
    }
}
UIApplicationMain(CommandLine.argc,CommandLine.unsafeArgv,nil,NSStringFromClass(TouchLayoutDelegate.self))
