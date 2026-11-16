import UIKit
import WebKit

/// Original-service authentication only; the game itself uses Swift/Metal.
/// Guest and Discord sessions belong to this app. No browser profile or OAuth
/// credential is read. Only secure original-site cookies cross its own stores.
final class NativeOriginalWorldSignInController:UIViewController,WKNavigationDelegate,WKUIDelegate,UITextFieldDelegate {
    typealias Connection=NativeOriginalWorldAuthentication.Connection
    var onConnection:((Connection)->Void)?
    private let store=WKWebsiteDataStore.default()
    private var web:WKWebView?
    private let body=UIView(),nativePanel=UIStackView(),message=UILabel()
    private let proceed=UIButton(type:.system),cancel=UIButton(type:.system),retry=UIButton(type:.system)
    private let guestName=UITextField(),guest=UIButton(type:.system),discord=UIButton(type:.system)
    private let loading=UIActivityIndicatorView(style:.medium)
    private var auth:NativeOriginalWorldAuthentication?,ownedSession:URLSession?
    private var epoch:UInt64=0,checking=false,guestAvailable=false

    override func viewDidLoad(){
        super.viewDidLoad();view.backgroundColor = .black
        message.textColor = .white;message.numberOfLines=3;message.font = .systemFont(ofSize:14)
        cancel.setTitle("BACK",for:.normal);cancel.addTarget(self,action:#selector(back),for:.touchUpInside)
        retry.setTitle("RETRY",for:.normal);retry.addTarget(self,action:#selector(reloadLogin),for:.touchUpInside)
        proceed.setTitle("CONTINUE IN NATIVE GAME",for:.normal);proceed.addTarget(self,action:#selector(verify),for:.touchUpInside)
        loading.color = .white;loading.hidesWhenStopped=true
        let spacer=UIView()
        let actions=UIStackView(arrangedSubviews:[cancel,loading,spacer,retry,proceed]);actions.axis = .horizontal;actions.spacing=12
        for button in [cancel,retry,proceed]{button.setContentCompressionResistancePriority(.required,for:.horizontal)}
        proceed.isHidden=true
        let row=UIStackView(arrangedSubviews:[actions,message]);row.axis = .vertical;row.spacing=4;row.translatesAutoresizingMaskIntoConstraints=false
        body.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(row);view.addSubview(body)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor,constant:12),row.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor,constant:-12),row.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor),row.heightAnchor.constraint(greaterThanOrEqualToConstant:48),body.topAnchor.constraint(equalTo:row.bottomAnchor,constant:8),body.leadingAnchor.constraint(equalTo:view.leadingAnchor),body.trailingAnchor.constraint(equalTo:view.trailingAnchor),body.bottomAnchor.constraint(equalTo:view.bottomAnchor)])
        let title=UILabel();title.text="JOIN THE ORIGINAL BROWSER WORLD";title.font = .systemFont(ofSize:23,weight:.bold);title.textColor = .white;title.textAlignment = .center;title.numberOfLines=2
        let hint=UILabel();hint.text="Play with people using play.samp.directory. Your game stays native.";hint.textColor = .lightGray;hint.font = .systemFont(ofSize:15);hint.textAlignment = .center;hint.numberOfLines=2
        guestName.placeholder="Player name";guestName.text=UserDefaults.standard.string(forKey:"playerName") ?? "Player";guestName.borderStyle = .roundedRect;guestName.backgroundColor = .white;guestName.textColor = .black;guestName.autocapitalizationType = .none;guestName.autocorrectionType = .no;guestName.keyboardType = .asciiCapable;guestName.returnKeyType = .go;guestName.delegate=self;guestName.accessibilityLabel="Original server guest name"
        guest.setTitle("PLAY AS GUEST",for:.normal);guest.addTarget(self,action:#selector(joinGuest),for:.touchUpInside);guest.accessibilityIdentifier="originalWorld.guest"
        discord.setTitle("SIGN IN WITH DISCORD",for:.normal);discord.addTarget(self,action:#selector(startDiscord),for:.touchUpInside);discord.accessibilityIdentifier="originalWorld.discord"
        nativePanel.axis = .vertical;nativePanel.spacing=18;nativePanel.translatesAutoresizingMaskIntoConstraints=false
        for item in [title,hint,guestName,guest,discord]{nativePanel.addArrangedSubview(item)}
        body.addSubview(nativePanel);NSLayoutConstraint.activate([nativePanel.centerXAnchor.constraint(equalTo:body.centerXAnchor),nativePanel.centerYAnchor.constraint(equalTo:body.centerYAnchor),nativePanel.widthAnchor.constraint(lessThanOrEqualToConstant:500),nativePanel.widthAnchor.constraint(equalTo:body.safeAreaLayoutGuide.widthAnchor,multiplier:0.75),guestName.heightAnchor.constraint(equalToConstant:42)])
        prepareSession()
    }
    override var supportedInterfaceOrientations:UIInterfaceOrientationMask{.allButUpsideDown}
    override func viewDidDisappear(_ animated:Bool){super.viewDidDisappear(animated);epoch &+= 1;auth?.cancel();checking=false}
    deinit{auth?.cancel()}
    private func busy(_ value:Bool,_ text:String?=nil){checking=value;proceed.isEnabled = !value;discord.isEnabled = !value;guest.isEnabled = !value && guestAvailable;value ? loading.startAnimating():loading.stopAnimating();if let text{message.text=text}}
    @objc private func back(){epoch &+= 1;auth?.cancel();web?.stopLoading();dismiss(animated:true)}
    private func prepareSession(){
        epoch &+= 1;let current=epoch;auth?.cancel();busy(true,"CHECKING THE ORIGINAL SERVER…")
        store.httpCookieStore.getAllCookies{[weak self] cookies in
            DispatchQueue.main.async {
                guard let self,self.epoch==current,self.isViewLoaded,!self.isBeingDismissed else{return}
                if self.ownedSession==nil {
                    let config=URLSessionConfiguration.ephemeral;config.requestCachePolicy = .reloadIgnoringLocalCacheData;config.timeoutIntervalForRequest=15;config.httpShouldSetCookies=true
                    config.httpAdditionalHeaders=["Accept":"application/json","Origin":"https://play.samp.directory","Referer":"https://play.samp.directory/"]
                    self.ownedSession=URLSession(configuration:config)
                }
                guard let session=self.ownedSession else{return}
                for cookie in NativeOriginalWorldProtocol.sessionCookies(cookies){session.configuration.httpCookieStorage?.setCookie(cookie)}
                do{self.auth=try NativeOriginalWorldAuthentication(session:session)}catch{self.busy(false,"CANNOT PREPARE THE ORIGINAL SERVER CONNECTION.");return}
                self.auth?.account{[weak self] result in
                    guard let self,self.epoch==current else{return}
                    switch result {
                    case .failure(let error):self.busy(false,error.message)
                    case .success(let account):
                        self.guestAvailable=account.available && account.guests;self.guest.isHidden = !account.guests;self.guestName.isHidden = !account.guests
                        self.busy(false,!account.available ? "THE ORIGINAL SERVER IS CURRENTLY UNAVAILABLE. TAP RETRY LATER.":account.guests ? "ENTER A NAME TO PLAY AS A GUEST, OR SIGN IN WITH DISCORD.":"THIS SERVER CURRENTLY REQUIRES SIGN-IN.")
                        if account.loggedIn{self.finishExisting()}
                    }
                }
            }
        }
    }
    @objc private func joinGuest(){
        guard !checking,guestAvailable,let auth else{return};guestName.resignFirstResponder()
        let name=(guestName.text ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty,name.utf16.count<=24 else{message.text="ENTER A NAME OF UP TO 24 CHARACTERS.";return}
        let current=epoch;busy(true,"JOINING THE ORIGINAL SERVER AS A GUEST…")
        auth.createGuest(name:name){[weak self] result in guard let self,self.epoch==current else{return};self.completed(result,epoch:current)}
    }
    private func finishExisting(){
        guard !checking,let auth else{return};let current=epoch;busy(true,"CONNECTING TO THE NATIVE GAME…")
        auth.bootstrap{[weak self] result in guard let self,self.epoch==current else{return};self.completed(result,epoch:current)}
    }
    private func completed(_ result:Result<Connection,NativeOriginalWorldAuthentication.Failure>,epoch current:UInt64){
        guard epoch==current else{return}
        // Preserve this app's own original-site session even if the following
        // build request failed. Never export a cookie value to tools or logs.
        let cookies=NativeOriginalWorldProtocol.sessionCookies(ownedSession?.configuration.httpCookieStorage?.cookies ?? [])
        let group=DispatchGroup()
        for cookie in cookies{group.enter();store.httpCookieStore.setCookie(cookie){group.leave()}}
        group.notify(queue:.main){[weak self]in
            guard let self,self.epoch==current else{return}
            switch result{case .failure(let error):self.busy(false,error.message)
            case .success(let connection):self.busy(false,"CONNECTED");self.web?.stopLoading();self.onConnection?(connection)}
        }
    }
    @objc private func verify(){if web != nil{prepareSession()}else{finishExisting()}}
    @objc private func reloadLogin(){if web != nil{startDiscord()}else{prepareSession()}}
    @objc private func startDiscord(){
        guard !checking else{return};guestName.resignFirstResponder();nativePanel.isHidden=true;proceed.isHidden=false
        if web==nil {
            let config=WKWebViewConfiguration();config.websiteDataStore=store
            let browser=WKWebView(frame:.zero,configuration:config);browser.navigationDelegate=self;browser.uiDelegate=self;browser.translatesAutoresizingMaskIntoConstraints=false
            body.addSubview(browser);NSLayoutConstraint.activate([browser.leadingAnchor.constraint(equalTo:body.leadingAnchor),browser.trailingAnchor.constraint(equalTo:body.trailingAnchor),browser.topAnchor.constraint(equalTo:body.topAnchor),browser.bottomAnchor.constraint(equalTo:body.bottomAnchor)]);web=browser
        }
        message.text="LOADING DISCORD SIGN-IN…";loading.startAnimating();web?.stopLoading();web?.load(URLRequest(url:NativeOriginalWorldProtocol.loginURL))
    }
    func textFieldShouldReturn(_ textField:UITextField)->Bool{joinGuest();return true}
    func textField(_ textField:UITextField,shouldChangeCharactersIn range:NSRange,replacementString string:String)->Bool{((textField.text ?? "")as NSString).replacingCharacters(in:range,with:string).utf16.count<=24}
    func webView(_ webView:WKWebView,didStartProvisionalNavigation navigation:WKNavigation!){loading.startAnimating()}
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){loading.stopAnimating();if webView.url?.host?.lowercased()=="play.samp.directory"{prepareSession()}else{message.text="SIGN IN WITH DISCORD BELOW, THEN CONTINUE."}}
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error){navigationFailed(error)}
    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error){navigationFailed(error)}
    private func navigationFailed(_ error:Error){let value=error as NSError;guard value.domain != NSURLErrorDomain || value.code != NSURLErrorCancelled else{return};loading.stopAnimating();message.text="SIGN-IN PAGE COULD NOT LOAD (\(value.code)). TAP RETRY."}
    func webViewWebContentProcessDidTerminate(_ webView:WKWebView){loading.stopAnimating();message.text="WEBKIT STOPPED THE SIGN-IN PAGE. TAP RETRY OR GO BACK TO USE GUEST ENTRY."}
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){
        if navigationAction.targetFrame?.isMainFrame==true,let url=navigationAction.request.url,url.host?.lowercased()=="play.samp.directory",!url.path.hasPrefix("/api/auth/"){decisionHandler(.cancel);DispatchQueue.main.async{[weak self]in self?.prepareSession()};return};decisionHandler(.allow)
    }
    func webView(_ webView:WKWebView,decidePolicyFor navigationResponse:WKNavigationResponse,decisionHandler:@escaping(WKNavigationResponsePolicy)->Void){
        if navigationResponse.isForMainFrame,let response=navigationResponse.response as?HTTPURLResponse,response.statusCode>=400{loading.stopAnimating();message.text="SIGN-IN WEBSITE RETURNED HTTP \(response.statusCode). TAP RETRY."};decisionHandler(.allow)
    }
    func webView(_ webView:WKWebView,createWebViewWith configuration:WKWebViewConfiguration,for navigationAction:WKNavigationAction,windowFeatures:WKWindowFeatures)->WKWebView?{if navigationAction.targetFrame==nil,let url=navigationAction.request.url,url.scheme?.lowercased()=="https"{webView.load(navigationAction.request)};return nil}
}
