import UIKit
import GameController

/// Owner-supplied DE artwork and recovered widget geometry, with ZGTA actions.
/// Animation timings below are independent choices; the IPA's runtime menu
/// animations have not been observed or claimed to be reproduced exactly.
final class MainMenuViewController: UIViewController {
    private let background=UIImageView(), portrait=UIImageView(), logo=UIImageView()
    private let fallbackLogo=UILabel(), attribution=UILabel()
    private var buttons:[NativeDETitleButton]=[]
    private var selected=0
    private var observers:[NSObjectProtocol]=[]
    private var handlers:[(GCControllerButtonInput,GCControllerButtonValueChangedHandler?)]=[]
    private var reduced:Bool {UIAccessibility.isReduceMotionEnabled || NativeAppSettings.shared.snapshot.reduceMenuMotion}
    override var canBecomeFirstResponder:Bool {true}
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor=UIColor(red:0.40,green:0.51,blue:0.33,alpha:1)
        let assets=NativeDEMenuAssets.shared
        background.image=assets.image("background");background.contentMode = .scaleToFill
        portrait.image=assets.image("portrait");portrait.contentMode = .scaleAspectFit
        logo.image=assets.image("logo");logo.contentMode = .scaleAspectFit
        for image in [background,portrait,logo] {image.isAccessibilityElement=false;view.addSubview(image)}
        fallbackLogo.text="ZGTA\nSAN ANDREAS";fallbackLogo.numberOfLines=2;fallbackLogo.textAlignment = .center
        fallbackLogo.textColor = .white;fallbackLogo.isHidden=logo.image != nil
        fallbackLogo.layer.shadowColor=UIColor.black.cgColor;fallbackLogo.layer.shadowOpacity=1;fallbackLogo.layer.shadowOffset=CGSize(width:2,height:2)
        view.addSubview(fallbackLogo)
        for (index,title) in ["MULTIPLAYER","GAME","OPTIONS"].enumerated() {
            let button=NativeDETitleButton(title:title,textureKey:["selectedPlay","selectedGame","selectedOptions"][index])
            button.accessibilityIdentifier="mainMenu.\(title.lowercased())"
            button.addAction(UIAction{[weak self] _ in self?.activate(index)},for:.touchUpInside)
            button.addTarget(self,action:#selector(pointerSelection(_:)),for:.touchDown)
            button.onHover={[weak self] in self?.select(index,sound:true)}
            buttons.append(button);view.addSubview(button)
        }
        attribution.text="ZGTA:SA";attribution.textColor=UIColor.white.withAlphaComponent(0.65)
        attribution.font=assets.font("body",size:10);attribution.accessibilityLabel="ZGTA San Andreas"
        view.addSubview(attribution);select(0,sound:false)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        background.frame=view.bounds
        let layout=NativeMainMenuLayout(bounds:view.bounds,safe:view.safeAreaLayoutGuide.layoutFrame)
        portrait.frame=layout.portrait;logo.frame=layout.logo;fallbackLogo.frame=layout.logo
        fallbackLogo.font=NativeDEMenuAssets.shared.font("menu",size:max(18,layout.fontSize*1.25))
        for (i,button) in buttons.enumerated() {
            button.frame=layout.buttons[i];button.apply(fontSize:layout.fontSize,scale:layout.scale,visualHeight:layout.visualRowHeight)
        }
        let safe=view.safeAreaLayoutGuide.layoutFrame
        attribution.frame=CGRect(x:safe.minX+10,y:safe.maxY-14,width:120,height:12)
    }
    override func viewDidAppear(_ animated:Bool) {
        super.viewDidAppear(animated);becomeFirstResponder();installControllers()
        observers=[NotificationCenter.default.addObserver(forName:.GCControllerDidConnect,object:nil,queue:.main){[weak self] _ in self?.installControllers()},
            NotificationCenter.default.addObserver(forName:UIApplication.didBecomeActiveNotification,object:nil,queue:.main){[weak self] _ in self?.restoreControllers();self?.installControllers()}]
        guard !reduced else{return}
        for (i,item) in ([logo,portrait] as [UIView]).enumerated() {
            item.alpha=0;UIView.animate(withDuration:0.25,delay:Double(i)*0.06,options:[.beginFromCurrentState,.allowUserInteraction]){item.alpha=1}
        }
    }
    override func viewDidDisappear(_ animated:Bool) {
        super.viewDidDisappear(animated);restoreControllers();observers.forEach{NotificationCenter.default.removeObserver($0)};observers=[]
    }
    @objc private func pointerSelection(_ sender:NativeDETitleButton) {if let i=buttons.firstIndex(of:sender){select(i,sound:true)}}
    private func select(_ index:Int,sound:Bool) {
        let next=(index+buttons.count)%buttons.count,changed=next != selected;selected=next
        for (i,button) in buttons.enumerated(){button.isSelected=i==selected}
        if changed && sound {NativeMenuAudio.shared.play(.highlight)}
    }
    private func activate(_ index:Int) {
        guard presentedViewController==nil,UIApplication.shared.applicationState == .active else{return}
        select(index,sound:false);NativeMenuAudio.shared.play(.start)
        let next:UIViewController
        switch index {
        case 0:
            let resources=NativeResourceStore.shared.snapshot
            next = resources.mode == .installed && !resources.hasPlayableInstallation
                ? NativeGameFilesViewController(coordinator:.shared) : HomeViewController()
        case 1:next=NativeGameManagementController()
        default:next=NativeOptionsViewController()
        }
        next.modalPresentationStyle = .fullScreen;present(next,animated:!reduced)
    }
    override func pressesBegan(_ presses:Set<UIPress>,with event:UIPressesEvent?) {
        guard presentedViewController==nil else {super.pressesBegan(presses,with:event);return}
        for press in presses {
            guard let key=press.key?.keyCode else{continue}
            switch key {
            case .keyboardUpArrow,.keyboardDownArrow,.keyboardReturnOrEnter,.keyboardSpacebar:
                guard NativeMenuKeyState.press(key) else{return}
                if key == .keyboardUpArrow {select(selected-1,sound:true)}
                else if key == .keyboardDownArrow {select(selected+1,sound:true)}
                else {activate(selected)}
                return
            default:break
            }
        };super.pressesBegan(presses,with:event)
    }
    override func pressesEnded(_ presses:Set<UIPress>,with event:UIPressesEvent?) {NativeMenuKeyState.release(presses);super.pressesEnded(presses,with:event)}
    override func pressesCancelled(_ presses:Set<UIPress>,with event:UIPressesEvent?) {NativeMenuKeyState.release(presses);super.pressesCancelled(presses,with:event)}
    private func restoreControllers(){for (button,handler) in handlers{button.pressedChangedHandler=handler};handlers=[]}
    private func installControllers() {
        func bind(_ button:GCControllerButtonInput,_ action:@escaping(MainMenuViewController)->Void) {
            guard !handlers.contains(where:{$0.0===button}) else{return}
            handlers.append((button,button.pressedChangedHandler));var edge=NativeReleaseEdge(pressed:button.isPressed)
            button.pressedChangedHandler={[weak self] _,_,pressed in DispatchQueue.main.async {
                guard let self,self.view.window != nil,self.presentedViewController==nil,UIApplication.shared.applicationState == .active else{return}
                if edge.update(pressed:pressed){action(self)}
            }}
        }
        for controller in GCController.controllers() {
            guard let pad=controller.extendedGamepad else{continue}
            bind(pad.dpad.up,{$0.select($0.selected-1,sound:true)});bind(pad.dpad.down,{$0.select($0.selected+1,sound:true)})
            bind(pad.buttonA,{$0.activate($0.selected)})
        }
    }
}

private final class NativeDETitleButton:UIButton {
    private let selectedImage=UIImageView(), selectedShadow=UIImageView()
    private let caption=UILabel()
    private var drawingScale:CGFloat=1,visualHeight:CGFloat=65
    var onHover:(()->Void)?
    init(title:String,textureKey:String) {
        super.init(frame:.zero);accessibilityLabel=title;isAccessibilityElement=true
        selectedImage.image=NativeDEMenuAssets.shared.image(textureKey)?.withRenderingMode(.alwaysTemplate);selectedImage.tintColor = .white
        selectedShadow.image=selectedImage.image
        // Serialized UE colors are linear values; UIKit expects encoded sRGB.
        func srgb(_ v:Double)->CGFloat {CGFloat(v <= 0.0031308 ? 12.92*v:1.055*pow(v,1/2.4)-0.055)}
        selectedShadow.tintColor=UIColor(red:srgb(0.097586997),green:srgb(0.250158012),blue:srgb(0.054480001),alpha:1)
        for item in [selectedShadow,selectedImage]{item.contentMode = .scaleToFill;item.isUserInteractionEnabled=false;addSubview(item)}
        caption.text=title;caption.numberOfLines=1;caption.adjustsFontSizeToFitWidth=true;caption.minimumScaleFactor=0.8
        caption.layer.shadowRadius=0;caption.isUserInteractionEnabled=false;addSubview(caption)
        addGestureRecognizer(UIHoverGestureRecognizer(target:self,action:#selector(hover(_:))))
        updateStyle()
    }
    required init?(coder:NSCoder){fatalError("Programmatic menu")}
    override var isSelected:Bool{didSet{updateStyle()}}
    override var isHighlighted:Bool{didSet{updateStyle()}}
    func apply(fontSize:CGFloat,scale:CGFloat,visualHeight:CGFloat){drawingScale=scale;self.visualHeight=visualHeight;caption.font=NativeDEMenuAssets.shared.font("menu",size:fontSize);setNeedsLayout();updateStyle()}
    override func layoutSubviews(){
        super.layoutSubviews();let height=min(bounds.height,max(26,visualHeight))
        let face=CGRect(x:0,y:(bounds.height-height)/2,width:bounds.width,height:height)
        selectedImage.frame=face;selectedShadow.frame=face.offsetBy(dx:4*drawingScale,dy:4*drawingScale)
        caption.frame=face.insetBy(dx:20*drawingScale,dy:0)
    }
    @objc private func hover(_ gesture:UIHoverGestureRecognizer){if gesture.state == .began{onHover?()}}
    private func updateStyle(){
        selectedImage.isHidden = !isSelected;selectedShadow.isHidden = !isSelected
        if selectedImage.image == nil {backgroundColor=isSelected ? UIColor.white.withAlphaComponent(0.9):.clear}
        caption.textColor=isSelected ? .black:.white
        caption.layer.shadowColor=UIColor(red:0.345,green:0.537,blue:0.259,alpha:1).cgColor
        caption.layer.shadowOpacity=isSelected ? 0:1
        let offset=(isHighlighted ? 6.0:4.0)*drawingScale;caption.layer.shadowOffset=CGSize(width:offset,height:offset)
        accessibilityTraits=isSelected ? [.button,.selected]:[.button]
    }
}
