import Foundation
import CoreGraphics

@main struct MenuGeometryChecks {
    static func main() {
        var checks=0
        func check(_ value:Bool,_ detail:String){checks += 1;precondition(value,detail)}
        let screens:[(String,CGFloat,CGFloat,CGFloat,CGFloat)]=[
            ("SE landscape",568,320,0,0),("SE3 landscape",667,375,0,0),
            ("mini landscape",812,375,50,21),("15Pro landscape",852,393,59,21),
            ("ProMax landscape",956,440,62,21),("iPad landscape",1194,834,0,20),
            ("original canvas",1920,1080,0,0)]
        for (name,width,height,inset,bottom) in screens {
            let bounds=CGRect(x:0,y:0,width:width,height:height)
            let safe=CGRect(x:inset,y:0,width:width-inset*2,height:height-bottom)
            let layout=NativeMainMenuLayout(bounds:bounds,safe:safe)
            check(layout.buttons.count==3,name+" entries")
            check(layout.logo.width>0 && abs(layout.logo.width-layout.logo.height)<0.001,name+" logo aspect")
            check(safe.contains(layout.logo),name+" visible logo")
            check(abs(layout.portrait.maxY-height)<0.001,name+" bottom anchored character")
            check(abs(layout.portrait.width-layout.portrait.height)<0.001,name+" portrait aspect")
            check(layout.fontSize.isFinite && layout.fontSize>0,name+" font scale")
            for (index,button) in layout.buttons.enumerated() {
                check(safe.contains(button),name+" reachable action\(index)")
                check(button.height>=44 && button.width>=44,name+" target size\(index)")
                if index>0 {check(button.minY>=layout.buttons[index-1].maxY,name+" nonoverlapping targets")}
            }
        }
        let original=NativeMainMenuLayout(bounds:CGRect(x:0,y:0,width:1920,height:1080),safe:CGRect(x:0,y:0,width:1920,height:1080))
        check(original.scale==1 && original.fontSize==50 && original.visualRowHeight==65,"recovered font/row design units")
        check(abs(original.buttons[0].minX-(1920*0.25779617-4.444214)*0.2)<0.001,"recovered left panel button anchor")
        check(original.portrait.maxY==1080,"recovered portrait alignment")
        print("PASS main menu geometry: \(checks) checks across compact/wide iPhone, iPad and original canvas")
    }
}
