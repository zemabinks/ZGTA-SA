import UIKit
import UniformTypeIdentifiers

/// Independently written SA file management. Only completed resource-store
/// verification enables installed mode; ISO inspection is never installation.
final class NativeGameFilesViewController:NativeDEPanelViewController,UIDocumentPickerDelegate,UITextFieldDelegate {
    private let coordinator:NativeGameFilesCoordinator
    private let column=UIStackView(),statusTitle=UILabel(),statusDetail=UILabel(),issues=UILabel()
    private let progressTitle=UILabel(),progressDetail=UILabel(),result=UILabel(),inspection=UILabel()
    private let progress=UIProgressView(progressViewStyle:.default),spinner=UIActivityIndicatorView(style:.medium)
    private let origin=UITextField(),progressPanel=UIStackView()
    private var sourceButtons:[UIButton]=[],observer:UUID?
    private var developmentButton:UIButton!,installedButton:UIButton!,verifyButton:UIButton!,cancelButton:UIButton!
    private var active=false,originInitialized=false,pickerKind:PickerKind?
    private enum PickerKind {case preparedFolder,iso}

    init(coordinator:NativeGameFilesCoordinator = .shared){self.coordinator=coordinator;super.init(title:"GAME FILES")}
    required init?(coder:NSCoder){fatalError("Programmatic menu")}
    deinit {if let observer{coordinator.removeObserver(observer)}}
    override func viewDidLoad(){
        super.viewDidLoad()
        let scroll=UIScrollView();scroll.keyboardDismissMode = .interactive;scroll.alwaysBounceVertical=true
        scroll.translatesAutoresizingMaskIntoConstraints=false;contentView.addSubview(scroll)
        column.axis = .vertical;column.spacing=14;column.translatesAutoresizingMaskIntoConstraints=false;scroll.addSubview(column)
        let preferredBottom=scroll.bottomAnchor.constraint(equalTo:contentView.bottomAnchor);preferredBottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo:contentView.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:contentView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo:contentView.topAnchor),preferredBottom,
            scroll.bottomAnchor.constraint(lessThanOrEqualTo:contentView.bottomAnchor),scroll.bottomAnchor.constraint(lessThanOrEqualTo:view.keyboardLayoutGuide.topAnchor),
            scroll.contentLayoutGuide.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor),
            column.centerXAnchor.constraint(equalTo:scroll.frameLayoutGuide.centerXAnchor),
            column.leadingAnchor.constraint(greaterThanOrEqualTo:scroll.contentLayoutGuide.leadingAnchor,constant:8),
            column.trailingAnchor.constraint(lessThanOrEqualTo:scroll.contentLayoutGuide.trailingAnchor,constant:-8),
            column.widthAnchor.constraint(lessThanOrEqualToConstant:800),
            column.topAnchor.constraint(equalTo:scroll.contentLayoutGuide.topAnchor,constant:6),
            column.bottomAnchor.constraint(equalTo:scroll.contentLayoutGuide.bottomAnchor,constant:-24)])
        let wide=column.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor,constant:-16);wide.priority = .defaultHigh;wide.isActive=true
        statusTitle.font=menuFont(size:26);statusTitle.textColor = .white;statusTitle.numberOfLines=0
        statusTitle.accessibilityIdentifier="gamefiles.status"
        configure(statusDetail);configure(issues);issues.textColor=UIColor(red:1,green:0.78,blue:0.36,alpha:1)
        column.addArrangedSubview(panel("RESOURCE STATUS",[statusTitle,statusDetail,issues]))
        developmentButton=menuButton("USE DEVELOPMENT RESOURCES"){[weak self] in self?.coordinator.setMode(.development)}
        installedButton=menuButton("USE INSTALLED RESOURCES"){[weak self] in self?.coordinator.setMode(.installed)}
        sourceButtons += [developmentButton,installedButton]
        column.addArrangedSubview(panel("ACTIVE SOURCE",[note("Development uses your prepared Mac resources and reusable cache. Installed mode uses a verified local installation; multiplayer still needs a reachable game server."),developmentButton,installedButton]))

        let importButton=menuButton("IMPORT / REPAIR PREPARED FOLDER"){[weak self] in self?.choose(.preparedFolder)}
        importButton.accessibilityIdentifier="gamefiles.import"
        verifyButton=menuButton("VERIFY INSTALLED FILES"){[weak self] in self?.coordinator.verifyInstalled()}
        sourceButtons += [importButton,verifyButton]
        column.addArrangedSubview(panel("LOCAL INSTALLATION",[
            note("Choose a prepared ZGTA:SA folder containing zgta-resources.json and its blobs folder. Only matching, verified resources are activated. Reimporting reuses verified content and repairs missing files."),importButton,verifyButton]))

        origin.placeholder="http://192.168.1.10:8766";origin.font=bodyFont(size:17);origin.textColor = .white;origin.tintColor = .white
        origin.backgroundColor=UIColor.white.withAlphaComponent(0.12);origin.keyboardType = .URL;origin.textContentType = .URL
        origin.autocapitalizationType = .none;origin.autocorrectionType = .no;origin.smartDashesType = .no;origin.smartQuotesType = .no
        origin.returnKeyType = .done;origin.delegate=self;origin.heightAnchor.constraint(greaterThanOrEqualToConstant:46).isActive=true
        origin.accessibilityLabel="Mac resource server origin"
        let inset=UIView(frame:CGRect(x:0,y:0,width:10,height:46));origin.leftView=inset;origin.leftViewMode = .always
        registerMenuControl(origin,activate:{[weak self] in self?.origin.becomeFirstResponder()})
        let cacheButton=menuButton("CACHE / REPAIR FROM MAC"){[weak self] in guard let self else{return};self.view.endEditing(true);self.coordinator.cacheDevelopment(self.origin.text ?? "")}
        cacheButton.accessibilityIdentifier="gamefiles.cache";sourceButtons.append(cacheButton)
        column.addArrangedSubview(panel("DEVELOPMENT RESOURCES",[
            note("Reuse the prepared resource package exposed by your Mac. Only missing or changed verified content is transferred. Cached files survive normal app updates; deleting or resetting the app removes its private cache."),origin,cacheButton]))

        let inspect=menuButton("INSPECT ORIGINAL ISO"){[weak self] in self?.choose(.iso)}
        inspect.accessibilityIdentifier="gamefiles.inspectISO";sourceButtons.append(inspect)
        configure(inspection);inspection.isHidden=true
        column.addArrangedSubview(panel("ORIGINAL GAME SOURCE",[
            note("Select your own original San Andreas ISO to inspect its ISO9660 file list. This step identifies installer containers only. InstallShield extraction and native conversion must finish before an ISO can become a playable installation. The ISO is never modified or deleted."),inspect,inspection]))

        progressPanel.axis = .vertical;progressPanel.spacing=8
        progressTitle.font=menuFont(size:23);progressTitle.textColor = .white;progressTitle.numberOfLines=0
        configure(progressDetail);progressDetail.font = .monospacedDigitSystemFont(ofSize:13,weight:.regular)
        progressDetail.accessibilityTraits.insert(.updatesFrequently)
        progress.progressTintColor=UIColor(red:1,green:0.84,blue:0.22,alpha:1)
        spinner.color = .white;spinner.hidesWhenStopped=true
        let heading=UIStackView(arrangedSubviews:[spinner,progressTitle]);heading.spacing=10;heading.alignment = .center
        cancelButton=menuButton("CANCEL CURRENT OPERATION"){[weak self] in self?.coordinator.cancel()}
        cancelButton.accessibilityIdentifier="gamefiles.cancel"
        progressPanel.addArrangedSubview(heading);progressPanel.addArrangedSubview(progress)
        progressPanel.addArrangedSubview(progressDetail);progressPanel.addArrangedSubview(cancelButton)
        column.addArrangedSubview(progressPanel)
        configure(result);result.accessibilityTraits.insert(.updatesFrequently);column.addArrangedSubview(result)
        column.addArrangedSubview(note("You may leave this screen while an operation runs. Return here for progress. Resources, source files and multiplayer account settings are kept separate."))
    }
    override func viewWillAppear(_ animated:Bool){
        super.viewWillAppear(animated);active=true
        if observer==nil {observer=coordinator.observe{[weak self] state in self?.render(state)}}
    }
    override func viewWillDisappear(_ animated:Bool){
        active=false;view.endEditing(true)
        if let observer{coordinator.removeObserver(observer);self.observer=nil}
        super.viewWillDisappear(animated)
    }
    func textFieldShouldReturn(_ textField:UITextField)->Bool{textField.resignFirstResponder();return true}
    private func configure(_ label:UILabel){label.font=bodyFont(size:15);label.textColor=UIColor.white.withAlphaComponent(0.88);label.numberOfLines=0}
    private func note(_ text:String)->UILabel{let label=UILabel();configure(label);label.text=text;return label}
    private func panel(_ title:String,_ items:[UIView])->UIView{
        let label=UILabel();label.text=title;label.font=menuFont(size:24);label.textColor=UIColor(red:1,green:0.84,blue:0.22,alpha:1);label.numberOfLines=0
        let inside=UIStackView(arrangedSubviews:[label]+items);inside.axis = .vertical;inside.spacing=8;inside.translatesAutoresizingMaskIntoConstraints=false
        let box=UIView();box.backgroundColor=UIColor.black.withAlphaComponent(0.4);box.layer.cornerRadius=12;box.addSubview(inside)
        NSLayoutConstraint.activate([inside.leadingAnchor.constraint(equalTo:box.leadingAnchor,constant:14),inside.trailingAnchor.constraint(equalTo:box.trailingAnchor,constant:-14),inside.topAnchor.constraint(equalTo:box.topAnchor,constant:12),inside.bottomAnchor.constraint(equalTo:box.bottomAnchor,constant:-12)])
        return box
    }
    private func render(_ state:NativeGameFilesCoordinator.State){
        guard isViewLoaded else{return};let resources=state.resources
        if !originInitialized {origin.text=resources.developmentOrigin ?? "";originInitialized=true}
        let bytes:(Int64)->String={ByteCountFormatter.string(fromByteCount:max(0,$0),countStyle:.file)}
        statusTitle.text=resources.mode == .installed ? (resources.hasPlayableInstallation ? "LOCAL INSTALLATION VERIFIED":"LOCAL INSTALLATION NEEDS ATTENTION") : "DEVELOPMENT RESOURCES"
        let installation=resources.installedContentID.map{"Installed identity: \($0)"} ?? "No verified local installation selected."
        statusDetail.text="\(installation)\nInstalled: \(resources.installedFiles) files · \(bytes(resources.installedBytes))\nReusable cache: \(resources.cachedFiles) files · \(bytes(resources.cachedBytes))" + (resources.developmentOrigin.map{"\nMac resource origin: \($0)"} ?? "")
        issues.text=resources.issues.prefix(12).joined(separator:"\n") + (resources.issues.count>12 ? "\nAnd \(resources.issues.count-12) more issues.":"")
        issues.isHidden=resources.issues.isEmpty
        for button in sourceButtons {button.isEnabled = !state.busy}
        installedButton.isEnabled = !state.busy && resources.hasPlayableInstallation
        verifyButton.isEnabled = !state.busy && resources.installedContentID != nil
        origin.isEnabled = !state.busy
        developmentButton.accessibilityValue=resources.mode == .development ? "Selected":""
        installedButton.accessibilityValue=resources.mode == .installed ? "Selected":""
        progressPanel.isHidden = !state.busy
        if let activity=state.activity {
            progressTitle.text=activity.cancelling ? "CANCELLING…":activity.kind.rawValue.uppercased()
            cancelButton.isEnabled = !activity.cancelling
            if let value=activity.progress {
                let fraction=value.totalBytes>0 ? Double(value.completedBytes)/Double(value.totalBytes):value.totalFiles>0 ? Double(value.completedFiles)/Double(value.totalFiles):0
                progress.progress=Float(min(1,max(0,fraction.isFinite ? fraction:0)))
                progressDetail.text="\(value.phase) · \(value.completedFiles) / \(value.totalFiles) files\n\(bytes(value.completedBytes)) / \(bytes(value.totalBytes))" + (value.currentPath.map{"\n\($0)"} ?? "")
                progress.isHidden=false;spinner.stopAnimating()
            }else{progress.isHidden=true;progressDetail.text=activity.kind == .inspecting ? "Reading bounded disc metadata. Original game bytes remain unchanged.":"Preparing verification…";spinner.startAnimating()}
        }else{spinner.stopAnimating()}
        result.text=state.message;result.isHidden=state.message==nil
        result.textColor=state.failed ? UIColor(red:1,green:0.65,blue:0.55,alpha:1):.white
        inspection.text=state.inspection?.detail;inspection.isHidden=state.inspection==nil
    }
    private func choose(_ kind:PickerKind){
        guard active,!coordinator.state.busy,presentedViewController==nil else{return}
        pickerKind=kind
        let types:[UTType]=kind == .preparedFolder ? [.folder]:[UTType(filenameExtension:"iso") ?? .data]
        let picker=UIDocumentPickerViewController(forOpeningContentTypes:types,asCopy:false)
        picker.delegate=self;picker.allowsMultipleSelection=false
        present(picker,animated:!menuMotionReduced)
    }
    func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController){pickerKind=nil}
    func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]){
        guard let kind=pickerKind else{return};pickerKind=nil
        guard let source=urls.first,!coordinator.state.busy else{return}
        // The shared coordinator, rather than this temporary picker/screen,
        // retains security-scoped access for the complete asynchronous job.
        if kind == .preparedFolder {coordinator.importPreparedFolder(source)}else{coordinator.inspectISO(source)}
    }
}
