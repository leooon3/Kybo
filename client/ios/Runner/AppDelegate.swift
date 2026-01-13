import Flutter
import UIKit
import workmanager

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // [FIX] Registra il task identifier PRIMA di tutto il resto
    // Deve corrispondere a quello in Info.plist
    WorkmanagerPlugin.registerTask(withIdentifier: "workmanager.background.task")

    GeneratedPluginRegistrant.register(with: self)
    
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
        GeneratedPluginRegistrant.register(with: registry)
    }
    
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}