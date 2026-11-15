import UIKit
import GameController
import CoreText

/// The owner's extracted resources are an optional private bundle folder.
/// Source releases contain the loader/layout, never the game's images/fonts.
final class NativeDEMenuAssets {
    static let shared = NativeDEMenuAssets()
    private struct Font: Decodable { let file: String; let postScriptName: String }
    private struct Manifest: Decodable {
        let images: [String:String]
        let fonts: [String:Font]
        let sounds: [String:String]
    }
    private var root: URL?
    private var manifest: Manifest?
    private var images: [String:UIImage] = [:]
    private init() { reload() }

    func reload() {
        root = Bundle.main.url(forResource:"OwnerMenu",withExtension:nil)
        if root == nil, let support = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first {
            let cached = support.appendingPathComponent("OwnerMenu",isDirectory:true)
            if FileManager.default.fileExists(atPath:cached.appendingPathComponent("manifest.json").path) {root=cached}
        }
        images.removeAll();manifest=nil
        if let root,let data=try? Data(contentsOf:root.appendingPathComponent("manifest.json")) {
            manifest=try? JSONDecoder().decode(Manifest.self,from:data)
        }
        for face in manifest?.fonts.values ?? Dictionary<String,Font>().values {
            if let url=resource(face.file) {CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)}
        }
    }
    private func resource(_ file:String)->URL? {
        guard !file.isEmpty, file == (file as NSString).lastPathComponent, !file.contains(".."), let root else{return nil}
        let url=root.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath:url.path) ? url:nil
    }
    func image(_ key:String)->UIImage? {
        if let cached=images[key] {return cached}
        guard let name=manifest?.images[key],let url=resource(name),let value=UIImage(contentsOfFile:url.path) else{return nil}
        images[key]=value;return value
    }
    func font(_ role:String,size:CGFloat)->UIFont {
        if let name=manifest?.fonts[role]?.postScriptName,let font=UIFont(name:name,size:size) {return font}
        return role == "body" ? .systemFont(ofSize:size,weight:.semibold):.boldSystemFont(ofSize:size)
    }
    func soundURL(key:String)->URL? {manifest?.sounds[key].flatMap(resource)}
    var hasOriginalPresentation:Bool {image("logo") != nil && image("background") != nil && image("portrait") != nil && manifest?.fonts["menu"] != nil}
}

/// Shared flat, high-contrast submenus; the title screen uses the recovered
/// 1920x1080 widget layout separately. No gameplay controller is replaced.
class NativeDEPanelViewController: UIViewController {
    let contentView=UIView()
    private let menuTitle:String
    private var entries:[Entry]=[]
    private var selected=0
    private struct Entry {
        weak var control:UIControl?
        var adjust:((Int)->Void)?
        var activate:(()->Void)?
    }
    private var oldHandlers:[(GCControllerButtonInput,GCControllerButtonValueChangedHandler?)]=[]
    private var observers:[NSObjectProtocol]=[]
    private var headingLabel=UILabel()
    private var background=UIImageView()
    var menuMotionReduced:Bool {UIAccessibility.isReduceMotionEnabled || NativeAppSettings.shared.snapshot.reduceMenuMotion}

    init(title:String) {menuTitle=title;super.init(nibName:nil,bundle:nil)}
    required init?(coder:NSCoder) {fatalError("Programmatic menu")}
    override var canBecomeFirstResponder:Bool {true}
    override func viewDidLoad() {
        super.viewDidLoad();view.backgroundColor=UIColor(red:0.37,green:0.46,blue:0.31,alpha:1)
        background.image=NativeDEMenuAssets.shared.image("background");background.contentMode = .scaleToFill
        background.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(background)
        let shade=UIView();shade.backgroundColor=UIColor.black.withAlphaComponent(0.58);shade.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(shade)
        headingLabel.text=menuTitle.uppercased();headingLabel.font=menuFont(size:34);headingLabel.textColor = .white
        headingLabel.layer.shadowColor=UIColor.black.cgColor;headingLabel.layer.shadowOpacity=1;headingLabel.layer.shadowOffset=CGSize(width:2,height:2);headingLabel.layer.shadowRadius=0
        headingLabel.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(headingLabel)
        let back=UIButton(type:.custom);back.setTitle("BACK",for:.normal);back.titleLabel?.font=menuFont(size:22);back.setTitleColor(.white,for:.normal)
        back.accessibilityLabel="Back";back.translatesAutoresizingMaskIntoConstraints=false
        back.addAction(UIAction{[weak self] _ in self?.closeMenu()},for:.touchUpInside);view.addSubview(back)
        contentView.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(contentView)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo:view.leadingAnchor),background.trailingAnchor.constraint(equalTo:view.trailingAnchor),
            background.topAnchor.constraint(equalTo:view.topAnchor),background.bottomAnchor.constraint(equalTo:view.bottomAnchor),
            shade.leadingAnchor.constraint(equalTo:view.leadingAnchor),shade.trailingAnchor.constraint(equalTo:view.trailingAnchor),
            shade.topAnchor.constraint(equalTo:view.topAnchor),shade.bottomAnchor.constraint(equalTo:view.bottomAnchor),
            headingLabel.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor,constant:24),
            headingLabel.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:12),
            headingLabel.trailingAnchor.constraint(lessThanOrEqualTo:back.leadingAnchor,constant:-16),
            back.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor,constant:-20),
            back.centerYAnchor.constraint(equalTo:headingLabel.centerYAnchor),back.heightAnchor.constraint(greaterThanOrEqualToConstant:44),back.widthAnchor.constraint(greaterThanOrEqualToConstant:75),
            contentView.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor,constant:24),
            contentView.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor,constant:-24),
            contentView.topAnchor.constraint(equalTo:headingLabel.bottomAnchor,constant:14),
            contentView.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-12)
        ])
    }
    func menuFont(size:CGFloat)->UIFont {NativeDEMenuAssets.shared.font("menu",size:size)}
    func bodyFont(size:CGFloat)->UIFont {NativeDEMenuAssets.shared.font("body",size:size)}
    func menuButton(_ title:String,action:@escaping()->Void)->UIButton {
        let button=UIButton(type:.custom);button.setTitle(title,for:.normal);button.titleLabel?.font=menuFont(size:24)
        button.setTitleColor(.white,for:.normal);button.setTitleColor(UIColor(white:0.82,alpha:1),for:.highlighted)
        button.contentHorizontalAlignment = .left;button.contentEdgeInsets=UIEdgeInsets(top:9,left:14,bottom:9,right:14)
        button.titleLabel?.numberOfLines=0;button.titleLabel?.layer.shadowColor=UIColor.black.cgColor
        button.titleLabel?.layer.shadowOpacity=1;button.titleLabel?.layer.shadowOffset=CGSize(width:2,height:2);button.titleLabel?.layer.shadowRadius=0
        button.heightAnchor.constraint(greaterThanOrEqualToConstant:44).isActive=true
        button.addAction(UIAction{_ in NativeMenuAudio.shared.play(.start);action()},for:.touchUpInside)
        registerMenuControl(button);return button
    }
    func registerMenuControl(_ control:UIControl,adjust:((Int)->Void)?=nil,activate:(()->Void)?=nil) {
        if let index=entries.firstIndex(where:{$0.control===control}) {entries[index].adjust=adjust;entries[index].activate=activate;return}
        entries.append(Entry(control:control,adjust:adjust,activate:activate))
    }
    func clearMenuControls() {entries.removeAll();selected=0}
    private var available:[Entry] {entries.filter{entry in
        guard let c=entry.control,c.window != nil,c.isDescendant(of:contentView),!c.isHidden,c.alpha>0.01,c.isEnabled else{return false}
        var parent=c.superview
        while let p=parent,p !== contentView {if p.isHidden || p.alpha<0.01{return false};parent=p.superview}
        return true
    }}
    private func moveSelection(_ delta:Int) {
        let active=available;guard !active.isEmpty else{return};selected=(selected+delta+active.count)%active.count
        for (i,entry) in active.enumerated() {entry.control?.layer.borderWidth=i==selected ? 1:0;entry.control?.layer.borderColor=UIColor.white.withAlphaComponent(0.7).cgColor}
        if let control=active[selected].control {
            var ancestor=control.superview
            while let next=ancestor {if let scroll=next as? UIScrollView {scroll.scrollRectToVisible(control.convert(control.bounds,to:scroll),animated:!menuMotionReduced);break};ancestor=next.superview}
            UIAccessibility.post(notification:.layoutChanged,argument:control)
        }
        NativeMenuAudio.shared.play(.highlight)
    }
    private func adjustSelection(_ delta:Int) {let a=available;guard !a.isEmpty else{return};selected=min(selected,a.count-1);a[selected].adjust?(delta)}
    private func activateSelection() {
        let a=available;guard !a.isEmpty else{return};selected=min(selected,a.count-1)
        if let activate=a[selected].activate {activate()}
        else {a[selected].control?.sendActions(for:.touchUpInside)}
    }
    @objc func closeMenu() {view.endEditing(true);NativeMenuAudio.shared.play(.back);dismiss(animated:!menuMotionReduced)}
    override func pressesBegan(_ presses:Set<UIPress>,with event:UIPressesEvent?) {
        guard presentedViewController==nil else {super.pressesBegan(presses,with:event);return}
        for press in presses {
            switch press.key?.keyCode {
            case .keyboardEscape:
                if NativeMenuKeyState.press(.keyboardEscape) {closeMenu()};return
            case .keyboardUpArrow:
                if NativeMenuKeyState.press(.keyboardUpArrow) {moveSelection(-1)};return
            case .keyboardDownArrow:
                if NativeMenuKeyState.press(.keyboardDownArrow) {moveSelection(1)};return
            case .keyboardLeftArrow:
                if NativeMenuKeyState.press(.keyboardLeftArrow) {adjustSelection(-1)};return
            case .keyboardRightArrow:
                if NativeMenuKeyState.press(.keyboardRightArrow) {adjustSelection(1)};return
            case .keyboardReturnOrEnter,.keyboardSpacebar:
                if let key=press.key?.keyCode,NativeMenuKeyState.press(key) {activateSelection()};return
            default:break
            }
        }
        super.pressesBegan(presses,with:event)
    }
    override func pressesEnded(_ presses:Set<UIPress>,with event:UIPressesEvent?) {NativeMenuKeyState.release(presses);super.pressesEnded(presses,with:event)}
    override func pressesCancelled(_ presses:Set<UIPress>,with event:UIPressesEvent?) {NativeMenuKeyState.release(presses);super.pressesCancelled(presses,with:event)}
    override func viewDidAppear(_ animated:Bool) {
        super.viewDidAppear(animated);becomeFirstResponder();installControllers()
        observers=[NotificationCenter.default.addObserver(forName:.GCControllerDidConnect,object:nil,queue:.main){[weak self] _ in self?.installControllers()},
            NotificationCenter.default.addObserver(forName:UIApplication.didBecomeActiveNotification,object:nil,queue:.main){[weak self] _ in self?.restoreControllers();self?.installControllers()}]
    }
    override func viewDidDisappear(_ animated:Bool) {super.viewDidDisappear(animated);restoreControllers();observers.forEach{NotificationCenter.default.removeObserver($0)};observers=[]}
    private func restoreControllers(){for (button,handler) in oldHandlers {button.pressedChangedHandler=handler};oldHandlers=[]}
    private func installControllers() {
        func bind(_ button:GCControllerButtonInput,_ action:@escaping(NativeDEPanelViewController)->Void) {
            guard !oldHandlers.contains(where:{$0.0===button}) else{return}
            oldHandlers.append((button,button.pressedChangedHandler));var edge=NativeReleaseEdge(pressed:button.isPressed)
            button.pressedChangedHandler={[weak self] _,_,pressed in DispatchQueue.main.async {
                guard let self,self.view.window != nil,self.presentedViewController==nil,UIApplication.shared.applicationState == .active else{return}
                if edge.update(pressed:pressed){action(self)}
            }}
        }
        for controller in GCController.controllers() {
            guard let pad=controller.extendedGamepad else{continue}
            bind(pad.dpad.up,{$0.moveSelection(-1)});bind(pad.dpad.down,{$0.moveSelection(1)})
            bind(pad.dpad.left,{$0.adjustSelection(-1)});bind(pad.dpad.right,{$0.adjustSelection(1)})
            bind(pad.buttonA,{$0.activateSelection()});bind(pad.buttonB,{$0.closeMenu()})
        }
    }
}

/// Shared across presented menu controllers: a held confirm/back key must be
/// released before it can activate the destination screen too.
enum NativeMenuKeyState {
    private static let lifecycleObservers:[NSObjectProtocol]=[
        NotificationCenter.default.addObserver(forName:UIApplication.willResignActiveNotification,object:nil,queue:.main){_ in reset()},
        NotificationCenter.default.addObserver(forName:.GCKeyboardDidDisconnect,object:nil,queue:.main){_ in reset()}
    ]
    static func reset(){NativeMenuKeyLatch.reset()}
    static func press(_ key:UIKeyboardHIDUsage)->Bool {_ = lifecycleObservers;return NativeMenuKeyLatch.press(Int(key.rawValue))}
    static func release(_ presses:Set<UIPress>) {for press in presses {if let key=press.key?.keyCode{NativeMenuKeyLatch.release(Int(key.rawValue))}}}
}
