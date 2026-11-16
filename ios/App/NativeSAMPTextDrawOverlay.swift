// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CoreGraphics

enum NativeSAMPTextDrawLayout {
    static func box(_ draw:NativeSAMPServerUI.TextDraw,viewport:CGRect)->CGRect {
        guard viewport.width>0,viewport.height>0 else{return .zero}
        let sx=viewport.width/640,sy=viewport.height/448
        let x=CGFloat(draw.x),y=CGFloat(draw.y)
        let glyphHeight=max(1,CGFloat(draw.letterHeight)*16)
        var rect:CGRect
        if draw.style>=4 {rect=CGRect(x:x,y:y,width:max(0,CGFloat(draw.lineWidth)),height:max(0,CGFloat(draw.lineHeight)))}
        else if draw.flags&8 != 0 {
            // Classic centre boxes exchange the two text-size axes.
            let width=max(1,abs(CGFloat(draw.lineHeight)))
            rect=CGRect(x:x-width/2,y:y-10,width:width,height:max(glyphHeight,abs(CGFloat(draw.lineWidth))))
        } else if draw.flags&4 != 0 {
            rect=CGRect(x:CGFloat(draw.lineWidth),y:y-10,width:max(1,x-CGFloat(draw.lineWidth)+5),height:max(glyphHeight,CGFloat(draw.lineHeight)-y+10))
        } else {
            let width=draw.lineWidth>draw.x ? CGFloat(draw.lineWidth)-x+5:max(1,CGFloat(draw.text.count)*CGFloat(draw.letterWidth)*16)
            rect=CGRect(x:x-5,y:y-10,width:width,height:max(glyphHeight,CGFloat(draw.lineHeight)-y+10))
        }
        return CGRect(x:viewport.minX+rect.minX*sx,y:viewport.minY+rect.minY*sy,width:rect.width*sx,height:rect.height*sy)
    }
}

#if canImport(UIKit)
import UIKit

/// Server-owned TextDraws over the native scene. Font/sprite resources remain
/// owner-local. Unsupported previews are reported and visibly marked rather
/// than replaced with an unrelated model. Full retail typography remains open.
final class NativeSAMPTextDrawOverlay:UIView {
    let store:NativeSAMPServerUI.Store
    private let send:(Data)->Bool
    private var widgets:[UInt16:NativeSAMPTextDrawWidget]=[:]
    private let cancel=UIButton(type:.system)
    private var observer:NSObjectProtocol?
    private var reported=Set<String>()
    var onSelectionChanged:((Bool)->Void)?
    var onUnsupported:((UInt16,String)->Void)?
    var onSendFailure:(()->Void)?
    var spriteProvider:((String)->UIImage?)?{didSet{render()}}
    var previewProvider:((NativeSAMPServerUI.TextDraw)->UIImage?)?{didSet{render()}}
    var viewportInsets:UIEdgeInsets?{didSet{setNeedsLayout()}}
    init(store:NativeSAMPServerUI.Store = NativeSAMPServerUI.Store(),onSend:@escaping(Data)->Bool){
        self.store=store;send=onSend;super.init(frame:.zero);isOpaque=false;backgroundColor = .clear;clipsToBounds=true
        cancel.setTitle("CANCEL",for:.normal);cancel.setTitleColor(.white,for:.normal);cancel.backgroundColor=UIColor.black.withAlphaComponent(0.75);cancel.layer.cornerRadius=8;cancel.accessibilityLabel="Cancel server selection";cancel.addTarget(self,action:#selector(cancelSelection),for:.touchUpInside);cancel.isHidden=true;addSubview(cancel)
        observer=NotificationCenter.default.addObserver(forName:NativeHUDResources.changed,object:nil,queue:.main){[weak self]_ in self?.render()}
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    deinit{if let observer{NotificationCenter.default.removeObserver(observer)}}
    override func point(inside point:CGPoint,with event:UIEvent?)->Bool {store.selection && super.point(inside:point,with:event)}
    func apply(_ event:NativeSAMPServerUI.Event){
        let old=store.selection;store.apply(event);if old != store.selection{onSelectionChanged?(store.selection)};render()
    }
    func clear(){let selected=store.selection;store.reset();reported.removeAll();render();if selected{onSelectionChanged?(false)}}
    override func layoutSubviews(){super.layoutSubviews();render()}
    private var viewport:CGRect{bounds.inset(by:viewportInsets ?? safeAreaInsets)}
    private func report(_ id:UInt16,_ reason:String){if reported.insert("\(id):\(reason)").inserted{onUnsupported?(id,reason)}}
    private func render(){
        guard Thread.isMainThread else{DispatchQueue.main.async{[weak self]in self?.render()};return}
        for id in Array(widgets.keys)where store.draws[id]==nil{widgets.removeValue(forKey:id)?.removeFromSuperview()}
        for id in store.draws.keys.sorted(){
            guard let model=store.draws[id]else{continue}
            let widget:NativeSAMPTextDrawWidget
            if let existing=widgets[id]{widget=existing}else{widget=NativeSAMPTextDrawWidget();widget.tag=Int(id);widget.addTarget(self,action:#selector(clicked(_:)),for:.touchUpInside);widgets[id]=widget;addSubview(widget)}
            widget.model=model;widget.viewport=viewport;widget.frame=NativeSAMPTextDrawLayout.box(model,viewport:viewport)
            widget.isEnabled=store.selection && model.selectable;widget.highlightColor=Self.rgba(store.highlight)
            widget.image=model.style==4 ? (spriteProvider?(model.text) ?? NativeHUDResources.shared.sprites[model.text]):model.style==5 ? previewProvider?(model):nil
            if model.style>=4 && widget.image==nil{report(id,model.style==4 ? "Server sprite is unavailable":"Server model preview is unavailable")}
            if model.style<4 && (model.style>=2 ? NativeHUDResources.shared.font2:NativeHUDResources.shared.font1)==nil{report(id,"Original HUD font assets unavailable; system-font fallback")}
            widget.accessibilityLabel=model.style==4 ? "Server image \(id)":model.style==5 ? "Server model preview \(model.modelID)":NativeSAMPTextCodec.stripColors(model.text)
            widget.accessibilityTraits=widget.isEnabled ? .button:.staticText;widget.setNeedsDisplay()
        }
        cancel.isHidden = !store.selection;cancel.frame=CGRect(x:viewport.maxX-118,y:viewport.minY+8,width:110,height:40);bringSubviewToFront(cancel)
    }
    @objc private func clicked(_ sender:UIControl){
        guard let packet=try? store.click(UInt16(sender.tag))else{return}
        if !send(packet){onSendFailure?()}
    }
    @objc private func cancelSelection(){
        guard let packet=try? store.click(nil)else{return}
        guard send(packet)else{onSendFailure?();return};store.apply(.selection(false,store.highlight));render();onSelectionChanged?(false)
    }
    fileprivate static func abgr(_ value:UInt32)->UIColor {UIColor(red:CGFloat(value&255)/255,green:CGFloat((value>>8)&255)/255,blue:CGFloat((value>>16)&255)/255,alpha:CGFloat(value>>24)/255)}
    fileprivate static func rgba(_ value:UInt32)->UIColor {UIColor(red:CGFloat(value>>24)/255,green:CGFloat((value>>16)&255)/255,blue:CGFloat((value>>8)&255)/255,alpha:CGFloat(value&255)/255)}
}

private final class NativeSAMPTextDrawWidget:UIControl {
    var model:NativeSAMPServerUI.TextDraw?
    var viewport=CGRect.zero
    var image:UIImage?
    var highlightColor=UIColor.white
    override var isHighlighted:Bool{didSet{setNeedsDisplay()}}
    override init(frame:CGRect){super.init(frame:frame);isOpaque=false;backgroundColor = .clear;isAccessibilityElement=true}
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override func draw(_ rect:CGRect){
        guard let model else{return}
        if model.usesBox{NativeSAMPTextDrawOverlay.abgr(model.boxColor).setFill();UIRectFill(bounds)}
        if isHighlighted && isEnabled{highlightColor.withAlphaComponent(0.25).setFill();UIRectFill(bounds)}
        if model.style>=4 {
            if let image{image.draw(in:bounds,blendMode:.normal,alpha:CGFloat(model.letterColor>>24)/255)}else{
                UIColor(white:0.2,alpha:0.7).setFill();UIRectFill(bounds)
                let message=model.style==4 ? "MISSING SPRITE":"MISSING MODEL PREVIEW"
                (message as NSString).draw(in:bounds.insetBy(dx:3,dy:3),withAttributes:[.font:UIFont.systemFont(ofSize:11),.foregroundColor:UIColor.lightGray])
            };return
        }
        let sy=viewport.height/448,sx=viewport.width/640,font=UIFont.systemFont(ofSize:max(1,CGFloat(model.letterHeight)*16*sy))
        let text=NativeSAMPTextCodec.stripColors(model.text).replacingOccurrences(of:"~n~",with:"\n"),lines=text.components(separatedBy:"\n")
        let alignment:NSTextAlignment=model.flags&8 != 0 ? .center:model.flags&4 != 0 ? .right:.left
        let x=viewport.minX+CGFloat(model.x)*sx-frame.minX,y=viewport.minY+CGFloat(model.y)*sy-frame.minY
        let origin=alignment == .left ? x:0
        if let context=UIGraphicsGetCurrentContext(),model.shadow>0{context.setShadow(offset:CGSize(width:CGFloat(model.shadow)*sx,height:CGFloat(model.shadow)*sy),blur:0,color:NativeSAMPTextDrawOverlay.abgr(model.backgroundColor).cgColor)}
        for (row,line)in lines.enumerated(){
            NativeBitmapLabel.draw(line,in:CGRect(x:origin,y:y+CGFloat(row)*font.pointSize*1.2,width:max(1,bounds.width-origin),height:font.pointSize*1.2),font:font,colour:NativeSAMPTextDrawOverlay.abgr(model.letterColor),alignment:alignment,menu:model.style>=2,heavy:model.style==3,fixed:!model.proportional,outline:CGFloat(model.outline)*sy)
        }
    }
}
#endif
