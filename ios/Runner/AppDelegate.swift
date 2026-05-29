import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    purgeRealtimeDatabasePersistenceCache()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
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
