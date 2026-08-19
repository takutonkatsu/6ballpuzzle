import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    super.scene(scene, openURLContexts: URLContexts)
    guard let url = URLContexts.first?.url else {
      return
    }
    (UIApplication.shared.delegate as? AppDelegate)?.handleFriendLink(
      url.absoluteString
    )
  }

  override func scene(
    _ scene: UIScene,
    continue userActivity: NSUserActivity
  ) {
    super.scene(scene, continue: userActivity)
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let url = userActivity.webpageURL else {
      return
    }
    (UIApplication.shared.delegate as? AppDelegate)?.handleFriendLink(
      url.absoluteString
    )
  }
}
