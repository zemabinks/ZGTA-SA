import UIKit

/// A keyboard-aware native server form. Keep text entry out of a modal alert,
/// whose first-run keyboard overlays can prevent editing and dismissal.
final class NativeSAMPConnectViewController:NativeDEPanelViewController {
    private let assets:ServerAddress,joinCode:String
    private let installed: Bool
    private let serverField=UITextField(),nameField=UITextField(),passwordField=UITextField()
    private let profile=UISegmentedControl(items:["0.3.7 / OPEN.MP","0.3.DL"])
    private let joinButton=UIButton(type:.system),message=UILabel()
    private var account:NativeMenuProfileClient?
    private var busy=false,active=false
    private var metadataTasks:[NativeResourceTask]=[]
    private var metadataGeneration:UInt64=0
    var onConnection:((NativeSAMPWorldConnection)->Void)?
    init(assets: ServerAddress, joinCode: String, installed: Bool) {
        self.assets = assets
        self.joinCode = joinCode
        self.installed = installed
        super.init(title: "SA-MP / OPEN.MP")
    }
    required init?(coder:NSCoder){fatalError("Programmatic connection menu")}
    override func viewDidLoad(){
        super.viewDidLoad();let scroll=NativeMenuScrollView();scroll.translatesAutoresizingMaskIntoConstraints=false
        scroll.keyboardDismissMode = .interactive;contentView.addSubview(scroll)
        let column=scroll.column;column.axis = .vertical;column.spacing=12
        let info=UILabel()
        info.text = installed ? "USING INSTALLED GAME FILES" : "GAME FILES: \(assets.display)"
        info.font=bodyFont(size:14);info.textColor = .lightGray;info.numberOfLines=0;column.addArrangedSubview(info)
        configure(serverField,title:"SERVER ADDRESS",placeholder:"server.example:7777",secret:false,column:column)
        serverField.keyboardType = .URL;serverField.accessibilityLabel="SA-MP server address"
        configure(nameField,title:"PLAYER NAME",placeholder:"Player name",secret:false,column:column)
        nameField.accessibilityLabel="SA-MP player name"
        configure(passwordField,title:"SERVER PASSWORD",placeholder:"Only if required",secret:true,column:column)
        passwordField.accessibilityLabel="SA-MP server password"
        serverField.text=UserDefaults.standard.string(forKey:"nativeSAMP.server")
        nameField.text=UserDefaults.standard.string(forKey:"nativeSAMP.nickname") ?? "ZGTA_"+String(UUID().uuidString.prefix(6))
        profile.selectedSegmentIndex=0;profile.accessibilityLabel="SA-MP protocol version"
        profile.addTarget(self,action:#selector(versionChanged),for:.valueChanged);column.addArrangedSubview(profile)
        registerMenuControl(profile,activate:{[weak self]in guard let self else{return};self.profile.selectedSegmentIndex=1-self.profile.selectedSegmentIndex;self.versionChanged()})
        joinButton.setTitle("JOIN 0.3.7 / OPEN.MP",for:.normal);joinButton.titleLabel?.font=menuFont(size:22)
        joinButton.backgroundColor = .white;joinButton.setTitleColor(.black,for:.normal)
        joinButton.heightAnchor.constraint(greaterThanOrEqualToConstant:48).isActive=true
        joinButton.addTarget(self,action:#selector(connect),for:.touchUpInside);registerMenuControl(joinButton);column.addArrangedSubview(joinButton)
        message.numberOfLines=0;message.font=bodyFont(size:14);message.textColor = .systemOrange;column.addArrangedSubview(message)
        let bottom=scroll.bottomAnchor.constraint(equalTo:contentView.bottomAnchor);bottom.priority = .defaultHigh
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo:contentView.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:contentView.trailingAnchor),scroll.topAnchor.constraint(equalTo:contentView.topAnchor),bottom,scroll.bottomAnchor.constraint(lessThanOrEqualTo:view.keyboardLayoutGuide.topAnchor)])
    }
    private func configure(_ field:UITextField,title:String,placeholder:String,secret:Bool,column:UIStackView){
        let label=UILabel();label.text=title;label.textColor = .white;label.font=bodyFont(size:14);column.addArrangedSubview(label)
        field.placeholder=placeholder;field.font=bodyFont(size:17);field.textColor = .white;field.tintColor = .white
        field.backgroundColor=UIColor.white.withAlphaComponent(0.12);field.isSecureTextEntry=secret
        field.autocapitalizationType = .none;field.autocorrectionType = .no;field.spellCheckingType = .no
        field.smartDashesType = .no;field.smartQuotesType = .no;field.returnKeyType = .done
        field.leftView=UIView(frame:CGRect(x:0,y:0,width:10,height:40));field.leftViewMode = .always
        field.heightAnchor.constraint(greaterThanOrEqualToConstant:44).isActive=true
        field.addTarget(self,action:#selector(endEntry),for:.editingDidEndOnExit)
        registerMenuControl(field,activate:{[weak field]in field?.becomeFirstResponder()});column.addArrangedSubview(field)
    }
    override func viewWillAppear(_ animated:Bool){super.viewWillAppear(animated);active=true}
    override func viewWillDisappear(_ animated:Bool){active=false;metadataGeneration &+= 1;metadataTasks.forEach{$0.cancel()};metadataTasks=[];account?.cancelPendingRequests();super.viewWillDisappear(animated)}
    @objc private func endEntry(){view.endEditing(true)}
    @objc private func versionChanged(){joinButton.setTitle(profile.selectedSegmentIndex==1 ? "JOIN 0.3.DL":"JOIN 0.3.7 / OPEN.MP",for:.normal)}
    private func verifyRuntime(_ completion:@escaping(Bool)->Void){
        metadataGeneration &+= 1;let epoch=metadataGeneration;var remaining=2,valid=true
        for path in ["game/native/samp-skins.json","game/native/original-weapons.json"] {
            let request=URLRequest(url:assets.path(path),cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:8)
            let task=NativeResourceTransport.boundedDataTask(with:request, maximumBytes:2_000_000){[weak self] data,response,_ in
                DispatchQueue.main.async {
                    guard let self,self.active,self.metadataGeneration==epoch else{return}
                    var accepted=false
                    if (response as?HTTPURLResponse)?.statusCode==200,let data,data.count<=2_000_000 {
                        if path.hasSuffix("samp-skins.json"){accepted=(try?NativeSAMPSkinCatalog(data:data)) != nil}
                        else if let object=try?JSONSerialization.jsonObject(with:data)as?[String:Any]{
                            accepted=NativeWeaponState(policy:.legacySAMP).installClientWeaponCatalog(object)
                        }
                    }
                    valid = valid && accepted;remaining-=1
                    if remaining==0{self.metadataTasks=[];completion(valid)}
                }
            };metadataTasks.append(task);task.resume()
        }
    }
    @objc private func connect(){
        guard active,!busy,let server=NativeSAMPAddress(serverField.text ?? ""),let name=nameField.text else{message.text="ENTER A VALID SERVER ADDRESS AND PLAYER NAME.";return}
        let version:NativeSAMPProtocol.Version=profile.selectedSegmentIndex==1 ? .dl:.v037,id=NativeSAMPIdentity.installation()
        guard (try?NativeSAMPProtocol.join(version:version,nickname:name,installationID:id,challenge:0)) != nil else{message.text="PLAYER NAMES MUST USE 3–24 ASCII CHARACTERS.";return}
        let binding = NativeResourceStore.shared.runtimeBinding
        if installed && (binding.mode != .installed || !binding.playable) {
            message.text = "VERIFY YOUR INSTALLED GAME FILES BEFORE CONNECTING."
            return
        }
        busy = true
        joinButton.isEnabled = false
        view.endEditing(true)
        let password = passwordField.text ?? ""
        let verifyAndConnect = { [weak self] in
            guard let self, self.active else { return }
            self.message.text = "CHECKING GAME FILES…"
            self.verifyRuntime { [weak self] ready in
                guard let self, self.active else { return }
                self.busy = false
                self.joinButton.isEnabled = true
                let sameInstallation = !self.installed || NativeResourceStore.shared.runtimeBinding == binding
                guard ready, sameInstallation else {
                    self.message.text = self.installed
                        ? "VERIFY OR REPAIR THE INSTALLED PACK. IT NEEDS THE LEGACY SKIN AND WEAPON DATA."
                        : "PREPARE THE SKIN AND WEAPON DATA ON YOUR MAC BEFORE CONNECTING."
                    return
                }
                UserDefaults.standard.set(server.display, forKey: "nativeSAMP.server")
                UserDefaults.standard.set(name, forKey: "nativeSAMP.nickname")
                self.message.text = "CONNECTING TO \(server.display)…"
                let transport = NativeSAMPClient(address: server.display, nickname: name,
                                                 version: version, installationID: id, password: password)
                self.onConnection?(NativeSAMPWorldConnection(client: transport, assetServer: self.assets))
            }
        }
        if installed {
            verifyAndConnect()
            return
        }
        message.text = "CONNECTING TO YOUR GAME FILES SERVER…"
        let client = NativeMenuProfileClient(server: assets)
        account = client
        client.connect(joinCode:joinCode){[weak self,weak client]result in
            guard let self,self.active,self.account === client else{return}
            switch result{
            case .failure(let error):
                self.busy = false
                self.joinButton.isEnabled = true
                self.message.text = error.message
            case .success:
                verifyAndConnect()
            }
        }
    }
}
