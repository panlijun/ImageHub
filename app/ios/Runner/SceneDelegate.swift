import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  #if DEBUG && IMAGEHUB_PHOTOS_UI_CI && targetEnvironment(simulator)
  private var photosAuthorizationCIWindow: UIWindow?

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    guard photosAuthorizationCIWindow == nil,
          let windowScene = scene as? UIWindowScene,
          let ciWindow = PhotosAuthorizationCI.makeWindow(for: windowScene) else {
      return
    }
    photosAuthorizationCIWindow = ciWindow
    ciWindow.makeKeyAndVisible()
  }
  #endif
}
