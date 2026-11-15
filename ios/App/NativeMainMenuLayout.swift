import Foundation
import CoreGraphics

/// Recovered 1920x1080 UMG anchors. The button hit rows alone expand on small
/// screens to remain 44pt tall; artwork retains its original proportions.
struct NativeMainMenuLayout {
    let logo: CGRect
    let portrait: CGRect
    let buttons: [CGRect]
    let fontSize: CGFloat
    let visualRowHeight: CGFloat
    let scale: CGFloat

    init(bounds: CGRect, safe: CGRect) {
        let width=max(1,bounds.width), height=max(1,bounds.height)
        scale=min(safe.width/1920,height/1080)
        let canvasWidth=1920*scale, canvasHeight=1080*scale
        let canvasX=safe.midX-canvasWidth/2, canvasY=bounds.midY-canvasHeight/2
        let leftWidth=(1920*0.25779617-4.444214)*scale
        let leftTop=canvasY+(1080*0.02256518+4.296274)*scale
        let leftHeight=(1080*0.95-4.296274-3.037109)*scale
        let logoSlot=CGRect(x:canvasX+4*scale,y:leftTop+leftHeight*0.02831765+2.814819*scale,
                            width:leftWidth-4*scale,height:leftHeight*(0.47459787-0.02831765)-4.226027*scale)
        let logoSide=min(logoSlot.width,logoSlot.height)
        logo=CGRect(x:logoSlot.midX-logoSide/2,y:logoSlot.midY-logoSide/2,width:logoSide,height:logoSide)
        let girlSlot=CGRect(x:bounds.minX+width*0.42,y:bounds.minY-height*0.03,width:width*0.58,height:height*1.03)
        let girlSide=min(girlSlot.width,girlSlot.height)
        portrait=CGRect(x:girlSlot.midX-girlSide/2,y:girlSlot.maxY-girlSide,width:girlSide,height:girlSide)
        fontSize=50*scale
        visualRowHeight=65*scale
        let rowHeight=max(44,visualRowHeight), x=canvasX+leftWidth*0.2
        // MULTIPLAYER is longer than START: preserve its left edge and font,
        // allowing its touch/selection rectangle to extend to the right.
        let rowWidth=max(leftWidth*0.6,390*scale)
        let top=min(leftTop+leftHeight*0.5+0.104034*scale,safe.maxY-rowHeight*3)
        buttons=(0..<3).map{CGRect(x:x,y:top+CGFloat($0)*rowHeight,width:rowWidth,height:rowHeight)}
    }
}
