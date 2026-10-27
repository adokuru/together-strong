import UIKit

@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        do {
            var baseURL = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? ""
            #if DEBUG && targetEnvironment(simulator)
            if let testURL = ProcessInfo.processInfo.environment["TS_TEST_API_ORIGIN"],
               let url = URL(string: testURL), ["localhost", "127.0.0.1"].contains(url.host ?? "") {
                baseURL = testURL
            }
            #endif
            let origin = try APIOrigin(baseURL)
            let store = WorkoutStore(api: APIClient(origin: origin),
                sessions: KeychainSessionStore(origin: origin), repository: try WorkoutRepository())
            window.rootViewController = UINavigationController(rootViewController: ConnectionViewController(store: store))
        } catch {
            let controller = UIViewController()
            controller.view.backgroundColor = .systemBackground
            let label = UILabel()
            label.text = "Together Strong\n\n" + error.localizedDescription
            label.numberOfLines = 0
            label.textAlignment = .center
            label.font = .preferredFont(forTextStyle: .body)
            label.translatesAutoresizingMaskIntoConstraints = false
            controller.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
                label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor),
            ])
            window.rootViewController = controller
        }
        window.makeKeyAndVisible()
    }
}
