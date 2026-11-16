// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Independently implemented protocol models. Wire/reference sources:
/// open.mp Shared/NetCode/{dialog,textdraw}.hpp72bf89ce4c8164f7f7b8271ffc7323bc45ea005f,
/// Pilot Apache2 client.go aa8c7971d2f3c8762a9f20c9ef35b42d5927a768.
enum NativeSAMPServerUI {
    enum DialogStyle:UInt8 {case message=0,input,list,password,tablist,headers
        var isList:Bool{self == .list || self == .tablist || self == .headers}
    }
    struct Dialog:Equatable {
        let id:Int16,style:DialogStyle,title:String,button1:String,button2:String,message:String
        var lines:[String]{var value=message.components(separatedBy:"\n").map{$0.hasSuffix("\r") ? String($0.dropLast()):$0};if value.last==""{value.removeLast()};return value}
        var rows:[String]{style.isList ? (style == .headers ? Array(lines.dropFirst()):lines):[]}
        var header:String?{style == .headers ? lines.first:nil}
    }
    struct TextDraw:Equatable {
        let id:UInt16,flags:UInt8,letterWidth:Float,letterHeight:Float,letterColor:UInt32
        let lineWidth:Float,lineHeight:Float,boxColor:UInt32,shadow:UInt8,outline:UInt8,backgroundColor:UInt32
        let style:UInt8,selectable:Bool,x:Float,y:Float,modelID:UInt16,rotation:SIMD3<Float>,zoom:Float,color1:Int16,color2:Int16
        var text:String
        var playerTextDraw:Bool{id>=2048}
        var usesBox:Bool{flags&1 != 0}
        var alignment:UInt8{(flags>>1)&7}
        var proportional:Bool{flags&16 != 0}
    }
    enum Event:Equatable {case dialog(Dialog?),showTextDraw(TextDraw),hideTextDraw(UInt16),textDrawString(UInt16,String),selection(Bool,UInt32)}
    static func decode(_ rpc:NativeSAMPProtocol.RPC,encoding:NativeSAMPTextCodec.Encoding = .windows1252)throws->Event? {
        var r=try NativeSAMPProtocol.Reader(rpc.data,bits:rpc.bits)
        func text(_ r:inout NativeSAMPProtocol.Reader)throws->String {let length=Int(try r.integer(1));return NativeSAMPTextCodec.decode(try r.bytes(length*8),encoding:encoding)}
        func id(_ r:inout NativeSAMPProtocol.Reader)throws->UInt16{let value=UInt16(try r.integer(2));guard value<2304 else{throw NativeSAMPProtocol.Error.invalid};return value}
        switch rpc.id {
        case 61:
            let dialogID=Int16(bitPattern:UInt16(try r.integer(2)))
            if dialogID == -1{return .dialog(nil)}
            guard dialogID>=0,let style=DialogStyle(rawValue:UInt8(try r.integer(1)))else{throw NativeSAMPProtocol.Error.invalid}
            let title=try text(&r),first=try text(&r),second=try text(&r)
            let body=NativeSAMPTextCodec.decode(try NativeSAMPTextCodec.compressed(&r),encoding:encoding)
            let dialog=Dialog(id:dialogID,style:style,title:title,button1:first,button2:second,message:body)
            guard dialog.rows.count<=4096 else{throw NativeSAMPProtocol.Error.invalid}
            return .dialog(dialog)
        case 134:
            let value=try id(&r),flags=UInt8(try r.integer(1)),lw=try r.float(),lh=try r.float(),color=try r.integer(4)
            let width=try r.float(),height=try r.float(),box=try r.integer(4),shadow=UInt8(try r.integer(1)),outline=UInt8(try r.integer(1)),background=try r.integer(4)
            let style=UInt8(try r.integer(1)),selectable=try r.integer(1),x=try r.float(),y=try r.float(),model=UInt16(try r.integer(2)),rotation=try r.vector(),zoom=try r.float()
            let c1=Int16(bitPattern:UInt16(try r.integer(2))),c2=Int16(bitPattern:UInt16(try r.integer(2))),count=Int(try r.integer(2))
            guard style<=5,selectable<=1,count<=1024,[lw,lh,width,height,x,y,zoom,rotation.x,rotation.y,rotation.z].allSatisfy({abs($0)<=1_000_000})else{throw NativeSAMPProtocol.Error.invalid}
            let string=NativeSAMPTextCodec.decode(try r.bytes(count*8),encoding:encoding)
            return .showTextDraw(TextDraw(id:value,flags:flags,letterWidth:lw,letterHeight:lh,letterColor:color,lineWidth:width,lineHeight:height,boxColor:box,shadow:shadow,outline:outline,backgroundColor:background,style:style,selectable:selectable==1,x:x,y:y,modelID:model,rotation:rotation,zoom:zoom,color1:c1,color2:c2,text:string))
        case 135:return .hideTextDraw(try id(&r))
        case 105:
            let value=try id(&r),count=Int(try r.integer(2));guard count<=1024 else{throw NativeSAMPProtocol.Error.invalid}
            return .textDrawString(value,NativeSAMPTextCodec.decode(try r.bytes(count*8),encoding:encoding))
        case 83:return .selection(try r.bit(),try r.integer(4))
        default:return nil
        }
    }
    static func dialogResponse(_ dialog:Dialog,accepted:Bool,selectedRow:Int?=nil,input:String="",encoding:NativeSAMPTextCodec.Encoding = .windows1252)throws->Data {
        guard dialog.id>=0 else{throw NativeSAMPProtocol.Error.invalid}
        var row:Int16 = -1,text=""
        if dialog.style.isList {
            if let selectedRow {
                guard selectedRow>=0,selectedRow<dialog.rows.count,selectedRow<=Int(Int16.max)else{throw NativeSAMPProtocol.Error.invalid}
                row=Int16(selectedRow);text=dialog.rows[selectedRow]
                if dialog.style != .list{text=String(text.split(separator:"\t",omittingEmptySubsequences:false).first ?? "")}
                text=NativeSAMPTextCodec.stripColors(text)
            }else if accepted && !dialog.rows.isEmpty{throw NativeSAMPProtocol.Error.invalid}
        } else if dialog.style == .input || dialog.style == .password {text=input}
        let bytes=try NativeSAMPTextCodec.encode(text,encoding:encoding)
        var w=NativeSAMPProtocol.Writer();w.integer(UInt32(UInt16(bitPattern:dialog.id)),size:2);w.integer(accepted ? 1:0,size:1);w.integer(UInt32(UInt16(bitPattern:row)),size:2);w.text8(bytes)
        return NativeSAMPProtocol.rpc(62,w)
    }
    static func clickTextDraw(_ id:UInt16?)throws->Data {
        guard id == nil || id!<2304 else{throw NativeSAMPProtocol.Error.invalid}
        var w=NativeSAMPProtocol.Writer();w.integer(UInt32(id ?? 0xffff),size:2);return NativeSAMPProtocol.rpc(83,w)
    }
    final class Store {
        private(set)var dialog:Dialog?,draws:[UInt16:TextDraw]=[:],selection=false,highlight:UInt32=0
        func reset(){dialog=nil;draws.removeAll();selection=false;highlight=0}
        func apply(_ event:Event){switch event{
        case .dialog(let value):dialog=value
        case .showTextDraw(let value):draws[value.id]=value
        case .hideTextDraw(let id):draws.removeValue(forKey:id)
        case .textDrawString(let id,let text):draws[id]?.text=text
        case .selection(let value,let color):selection=value;highlight=color
        }}
        func click(_ id:UInt16?)throws->Data {
            guard selection else{throw NativeSAMPProtocol.Error.invalid}
            if let id{guard draws[id]?.selectable == true else{throw NativeSAMPProtocol.Error.invalid}}
            return try clickTextDraw(id)
        }
    }
}

#if canImport(UIKit)
import UIKit

/// Functional native server dialog. Replacements/disconnects call invalidate()
/// without answering the stale dialog. The caller sends on its current session.
final class NativeSAMPDialogController:UIViewController,UITableViewDataSource,UITableViewDelegate {
    let dialog:NativeSAMPServerUI.Dialog
    let encoding:NativeSAMPTextCodec.Encoding
    private let submit:(Data)->Bool
    private var active=true,selectedRow:Int?
    private let field=UITextField(),table=UITableView(frame:.zero,style:.plain),errorLabel=UILabel()
    init(dialog:NativeSAMPServerUI.Dialog,encoding:NativeSAMPTextCodec.Encoding = .windows1252,onResponse:@escaping(Data)->Bool){
        self.dialog=dialog;self.encoding=encoding;submit=onResponse;selectedRow=dialog.rows.isEmpty ? nil:0
        super.init(nibName:nil,bundle:nil);modalPresentationStyle = .overFullScreen
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override var canBecomeFirstResponder:Bool{true}
    override var keyCommands:[UIKeyCommand]?{[UIKeyCommand(input:UIKeyCommand.inputEscape,modifierFlags:[],action:#selector(cancelDialog)),UIKeyCommand(input:"\r",modifierFlags:[],action:#selector(acceptDialog))]}
    func invalidate(){active=false;dismiss(animated:false)}
    override func viewDidLoad(){
        super.viewDidLoad();view.backgroundColor=UIColor.black.withAlphaComponent(0.55)
        let panel=UIView();panel.translatesAutoresizingMaskIntoConstraints=false;panel.backgroundColor=UIColor(white:0.07,alpha:0.98);panel.layer.borderWidth=1;panel.layer.borderColor=UIColor.gray.cgColor;panel.layer.cornerRadius=6;view.addSubview(panel)
        let stack=UIStackView();stack.axis = .vertical;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=false;panel.addSubview(stack)
        let title=UILabel();title.text=NativeSAMPTextCodec.stripColors(dialog.title);title.textColor = .white;title.font = .boldSystemFont(ofSize:20);title.numberOfLines=2;stack.addArrangedSubview(title)
        if dialog.style.isList {
            table.dataSource=self;table.delegate=self;table.backgroundColor = .clear;table.rowHeight=44;table.separatorColor = .darkGray;stack.addArrangedSubview(table)
            let tableHeight=table.heightAnchor.constraint(equalToConstant:min(240,CGFloat(dialog.rows.count)*44+(dialog.header == nil ? 0:36)));tableHeight.priority = .defaultHigh;tableHeight.isActive=true
            if let header=dialog.header{let label=UILabel(frame:CGRect(x:0,y:0,width:480,height:36));label.text=NativeSAMPTextCodec.stripColors(header);label.font = .boldSystemFont(ofSize:15);label.textColor = .lightGray;table.tableHeaderView=label}
        }else{
            let body=UITextView();body.isEditable=false;body.isSelectable=true;body.backgroundColor = .clear;body.textColor = .white;body.font = .systemFont(ofSize:16);body.text=NativeSAMPTextCodec.stripColors(dialog.message);body.textContainerInset = .zero;stack.addArrangedSubview(body);let bodyHeight=body.heightAnchor.constraint(equalToConstant:dialog.style == .message ? 160:72);bodyHeight.priority = .defaultHigh;bodyHeight.isActive=true
        }
        if dialog.style == .input || dialog.style == .password {
            field.borderStyle = .roundedRect;field.backgroundColor=UIColor(white:0.15,alpha:1);field.textColor = .white;field.autocorrectionType = .no;field.autocapitalizationType = .none;field.smartQuotesType = .no;field.smartDashesType = .no;field.isSecureTextEntry=dialog.style == .password;field.returnKeyType = .go;field.accessibilityLabel=dialog.style == .password ? "Server password":"Server dialog input";field.addTarget(self,action:#selector(acceptDialog),for:.editingDidEndOnExit);stack.addArrangedSubview(field)
        }
        errorLabel.textColor = .systemRed;errorLabel.font = .systemFont(ofSize:13);errorLabel.numberOfLines=2;errorLabel.isHidden=true;stack.addArrangedSubview(errorLabel)
        let buttons=UIStackView();buttons.axis = .horizontal;buttons.spacing=16;buttons.distribution = .fillEqually
        for (text,action) in [(dialog.button1,#selector(acceptDialog)),(dialog.button2,#selector(cancelDialog))]where !text.isEmpty {
            let button=UIButton(type:.system);button.setTitle(NativeSAMPTextCodec.stripColors(text),for:.normal);button.setTitleColor(.white,for:.normal);button.titleLabel?.font = .boldSystemFont(ofSize:17);button.addTarget(self,action:action,for:.touchUpInside);button.heightAnchor.constraint(equalToConstant:40).isActive=true;buttons.addArrangedSubview(button)
        }
        stack.addArrangedSubview(buttons)
        let centre=panel.centerYAnchor.constraint(equalTo:view.safeAreaLayoutGuide.centerYAnchor);centre.priority = .defaultHigh
        let width=panel.widthAnchor.constraint(equalTo:view.safeAreaLayoutGuide.widthAnchor,constant:-40);width.priority = .defaultHigh
        NSLayoutConstraint.activate([panel.centerXAnchor.constraint(equalTo:view.centerXAnchor),centre,panel.widthAnchor.constraint(lessThanOrEqualToConstant:600),width,panel.topAnchor.constraint(greaterThanOrEqualTo:view.safeAreaLayoutGuide.topAnchor,constant:8),panel.bottomAnchor.constraint(lessThanOrEqualTo:view.keyboardLayoutGuide.topAnchor,constant:-8),stack.leadingAnchor.constraint(equalTo:panel.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:panel.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:panel.topAnchor,constant:14),stack.bottomAnchor.constraint(equalTo:panel.bottomAnchor,constant:-14)])
    }
    override func viewDidAppear(_ animated:Bool){super.viewDidAppear(animated);if dialog.style == .input || dialog.style == .password{field.becomeFirstResponder()}else{becomeFirstResponder()};if let selectedRow{table.selectRow(at:IndexPath(row:selectedRow,section:0),animated:false,scrollPosition:.none)}}
    func tableView(_ tableView:UITableView,numberOfRowsInSection section:Int)->Int{dialog.rows.count}
    func tableView(_ tableView:UITableView,cellForRowAt indexPath:IndexPath)->UITableViewCell{
        let cell=UITableViewCell(style:.default,reuseIdentifier:nil);cell.backgroundColor = .clear;cell.textLabel?.text=NativeSAMPTextCodec.stripColors(dialog.rows[indexPath.row]);cell.textLabel?.textColor = .white;cell.textLabel?.font = .monospacedSystemFont(ofSize:15,weight:.regular);return cell
    }
    func tableView(_ tableView:UITableView,didSelectRowAt indexPath:IndexPath){selectedRow=indexPath.row}
    @objc private func acceptDialog(){answer(true)}
    @objc private func cancelDialog(){answer(false)}
    private func answer(_ accepted:Bool){
        guard active else{return}
        do{
            let packet=try NativeSAMPServerUI.dialogResponse(dialog,accepted:accepted,selectedRow:selectedRow,input:field.text ?? "",encoding:encoding)
            guard submit(packet)else{errorLabel.text="The response could not be queued. Please retry.";errorLabel.isHidden=false;return}
            active=false;field.text="";dismiss(animated:true)
        }catch{errorLabel.text="Input is too long or cannot be encoded for this server.";errorLabel.isHidden=false}
    }
}
#endif
