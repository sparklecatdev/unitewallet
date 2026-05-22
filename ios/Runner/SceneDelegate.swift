import SwiftUI
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: UniteRootView())
        self.window = window
        window.makeKeyAndVisible()

        handle(urlContexts: connectionOptions.urlContexts)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        handle(urlContexts: URLContexts)
    }

    private func handle(urlContexts: Set<UIOpenURLContext>) {
        guard let url = urlContexts.first?.url else { return }
        NotificationCenter.default.post(name: .walletConnectPairURI, object: url.absoluteString)
    }
}
