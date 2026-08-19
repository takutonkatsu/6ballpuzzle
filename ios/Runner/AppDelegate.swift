import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var deepLinkChannel: FlutterMethodChannel?
  private var pendingFriendLink: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    purgeRealtimeDatabasePersistenceCache()
    if let url = launchOptions?[.url] as? URL {
      pendingFriendLink = url.absoluteString
    }
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      configureShareImageChannel(binaryMessenger: controller.binaryMessenger)
      configureDeepLinkChannel(binaryMessenger: controller.binaryMessenger)
    }
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HexagonShareImage") {
      configureShareImageChannel(binaryMessenger: registrar.messenger())
      configureDeepLinkChannel(binaryMessenger: registrar.messenger())
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    handleFriendLink(url.absoluteString)
    return super.application(app, open: url, options: options)
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
       let url = userActivity.webpageURL {
      handleFriendLink(url.absoluteString)
    }
    return super.application(
      application,
      continue: userActivity,
      restorationHandler: restorationHandler
    )
  }

  private func configureDeepLinkChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "hexagon/deep_link",
      binaryMessenger: binaryMessenger
    )
    deepLinkChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getInitialFriendLink" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.pendingFriendLink)
    }
  }

  func handleFriendLink(_ link: String) {
    pendingFriendLink = link
    deepLinkChannel?.invokeMethod("onFriendLink", arguments: link)
  }

  private func configureShareImageChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "hexagon/share_image",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "shareResultImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let imageBytes = arguments["imageBytes"] as? FlutterStandardTypedData,
        !imageBytes.data.isEmpty
      else {
        result(FlutterError(
          code: "empty_image",
          message: "Share image bytes are empty.",
          details: nil
        ))
        return
      }

      let title = (arguments["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      let text = (arguments["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      guard UIImage(data: imageBytes.data) != nil else {
        result(FlutterError(
          code: "decode_failed",
          message: "Share image bytes could not be decoded.",
          details: nil
        ))
        return
      }

      let shareDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("hexagon_share", isDirectory: true)
      do {
        if FileManager.default.fileExists(atPath: shareDirectory.path) {
          let oldItems = try FileManager.default.contentsOfDirectory(
            at: shareDirectory,
            includingPropertiesForKeys: nil
          )
          for item in oldItems {
            try? FileManager.default.removeItem(at: item)
          }
        } else {
          try FileManager.default.createDirectory(
            at: shareDirectory,
            withIntermediateDirectories: true
          )
        }
      } catch {
        result(FlutterError(
          code: "share_file_prepare_failed",
          message: error.localizedDescription,
          details: nil
        ))
        return
      }

      let imageURL = shareDirectory.appendingPathComponent("hexagon_result.png")
      do {
        try imageBytes.data.write(to: imageURL, options: .atomic)
      } catch {
        result(FlutterError(
          code: "share_file_write_failed",
          message: error.localizedDescription,
          details: nil
        ))
        return
      }

      var items: [Any] = [imageURL]
      if let text, !text.isEmpty {
        items.append(text)
      }

      DispatchQueue.main.async {
        guard let presenter = self?.topViewController() else {
          result(FlutterError(
            code: "no_presenter",
            message: "No view controller is available for sharing.",
            details: nil
          ))
          return
        }
        let activityController = UIActivityViewController(
          activityItems: items,
          applicationActivities: nil
        )
        if let title, !title.isEmpty {
          activityController.setValue(title, forKey: "subject")
        }
        if let popover = activityController.popoverPresentationController {
          popover.sourceView = presenter.view
          popover.sourceRect = CGRect(
            x: presenter.view.bounds.midX,
            y: presenter.view.bounds.midY,
            width: 1,
            height: 1
          )
          popover.permittedArrowDirections = []
        }
        presenter.present(activityController, animated: true)
        result(true)
      }
    }
  }

  private func topViewController() -> UIViewController? {
    let activeScene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    let root = activeScene?.windows.first { $0.isKeyWindow }?.rootViewController
      ?? window?.rootViewController
    var top = root
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  private func purgeRealtimeDatabasePersistenceCache() {
    let fileManager = FileManager.default
    let purgePrefix = "firebase-rtdb-cache-purge-"
    let transientCachePurgeKey = "purged_transient_sdk_caches_v1"
    let transientCacheLimitBytes: UInt64 = 200 * 1024 * 1024

    if let temporaryItems = try? fileManager.contentsOfDirectory(
      at: fileManager.temporaryDirectory,
      includingPropertiesForKeys: nil
    ) {
      for item in temporaryItems where item.lastPathComponent.hasPrefix(purgePrefix) {
        DispatchQueue.global(qos: .utility).async {
          try? FileManager.default.removeItem(at: item)
        }
      }
    }

    if let cachesDirectory = fileManager.urls(
         for: .cachesDirectory,
         in: .userDomainMask
       ).first,
       shouldPurgeTransientCaches(
         at: cachesDirectory,
         limitBytes: transientCacheLimitBytes,
         defaultsKey: transientCachePurgeKey
       ) {
      if let cacheItems = try? fileManager.contentsOfDirectory(
        at: cachesDirectory,
        includingPropertiesForKeys: nil
      ) {
        for item in cacheItems {
          try? fileManager.removeItem(at: item)
        }
      }
      UserDefaults.standard.set(true, forKey: transientCachePurgeKey)
    }

    var firebaseCacheDirectories: [URL] = []

    if let documentsDirectory = fileManager.urls(
      for: .documentDirectory,
      in: .userDomainMask
    ).first {
      firebaseCacheDirectories.append(documentsDirectory.appendingPathComponent("firebase"))
    }

    if let cachesDirectory = fileManager.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    ).first {
      firebaseCacheDirectories.append(cachesDirectory.appendingPathComponent("firebase"))
    }

    for directory in firebaseCacheDirectories where fileManager.fileExists(atPath: directory.path) {
      let destination = fileManager.temporaryDirectory
        .appendingPathComponent("\(purgePrefix)\(UUID().uuidString)")

      do {
        try fileManager.moveItem(at: directory, to: destination)
        DispatchQueue.global(qos: .utility).async {
          try? FileManager.default.removeItem(at: destination)
        }
      } catch {
        try? fileManager.removeItem(at: directory)
      }
    }
  }

  private func shouldPurgeTransientCaches(
    at directory: URL,
    limitBytes: UInt64,
    defaultsKey: String
  ) -> Bool {
    if !UserDefaults.standard.bool(forKey: defaultsKey) {
      return true
    }
    return directorySize(at: directory) > limitBytes
  }

  private func directorySize(at directory: URL) -> UInt64 {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
      options: [.skipsHiddenFiles],
      errorHandler: nil
    ) else {
      return 0
    }

    var totalSize: UInt64 = 0
    for case let fileURL as URL in enumerator {
      guard let values = try? fileURL.resourceValues(
        forKeys: [.isRegularFileKey, .fileSizeKey]
      ), values.isRegularFile == true else {
        continue
      }
      totalSize += UInt64(values.fileSize ?? 0)
      if totalSize > UInt64.max / 2 {
        break
      }
    }
    return totalSize
  }
}
