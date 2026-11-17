import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let resourceIdleOwner=UUID()
    private var resourceObserver:UUID?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NativeResourceSession.activate()
        resourceObserver=NativeGameFilesCoordinator.shared.observe{[weak self] state in
            guard let self else{return}
            NativeGameplayIdleTimer.shared.setResourceActive(self.resourceIdleOwner,state.busy && UIApplication.shared.applicationState == .active)
        }
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = MainMenuViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
    func applicationDidBecomeActive(_ application:UIApplication){
        NativeGameplayIdleTimer.shared.setResourceActive(resourceIdleOwner,NativeGameFilesCoordinator.shared.state.busy)
    }
    func applicationWillResignActive(_ application:UIApplication){
        NativeGameplayIdleTimer.shared.setResourceActive(resourceIdleOwner,false)
    }
}
