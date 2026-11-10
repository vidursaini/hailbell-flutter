import Combine
import Flutter
import UIKit
import UserNotifications

/// The Flutter side of Hailbell on iOS. Every call goes to the native SDK in `Vendor/` (copied from
/// sdk/swift by tool/sync_native.sh), which draws the chat and talks to the server. This class only
/// translates between Dart and Swift, and takes the APNs token and notification taps from the app
/// delegate, which Flutter forwards to plugins.
public final class HailbellPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    /// The channel of the engine that configured Hailbell, for calls into Dart.
    private static var activeChannel: FlutterMethodChannel?
    private static var configured = false
    /// Taps that arrived before Dart configured Hailbell, as after a cold launch from a notification.
    private static var pendingTaps: [UNNotificationResponse] = []
    private static var purchases: [(id: String, purchased: () -> Void)] = []
    private static var lastToken: Data?

    private let channel: FlutterMethodChannel
    private var unread: AnyCancellable?

    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "hailbell", binaryMessenger: registrar.messenger())
        let instance = HailbellPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
        FlutterEventChannel(name: "hailbell/unread_count", binaryMessenger: registrar.messenger()).setStreamHandler(instance)
        registrar.addApplicationDelegate(instance)
        MainActor.assumeIsolated { adoptNotificationDelegate() }
    }

    /// Flutter's app delegate forwards notification callbacks to plugins, but only once it is the
    /// notification center's delegate. When the app hasn't set one, make it so. When another object
    /// is the delegate (some packages set their own), it must forward Hailbell's taps itself.
    @MainActor
    private static func adoptNotificationDelegate() {
        let center = UNUserNotificationCenter.current()
        guard center.delegate == nil, let app = UIApplication.shared.delegate as? FlutterAppLifeCycleProvider else { return }
        center.delegate = app
    }

    // MARK: Dart calls

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        MainActor.assumeIsolated {
            self.handleOnMain(call.method, Arguments(args), result: result)
        }
    }

    @MainActor
    private func handleOnMain(_ method: String, _ args: Arguments, result: @escaping FlutterResult) {
        switch method {
        case "configure":
            guard let appId = args.string("appId"), let baseURL = URL(string: args.string("baseUrl") ?? "https://api.hailbell.com") else {
                return result(FlutterError(code: "bad_arguments", message: "configure needs an appId and a valid baseUrl.", details: nil))
            }
            Self.activeChannel = channel
            // A second configure would attach the chat twice; only redo it for another App ID or server.
            if Hailbell.shared.client?.appId != appId || Hailbell.shared.client?.baseURL != baseURL {
                Hailbell.configure(appId: appId, baseURL: baseURL)
            }
            Self.configured = true
            Self.setOpenHandler(args.bool("pushOpenHandler") == true)
            Self.registerIfAllowed()
            Self.handlePendingTaps()
            result(nil)
        case "open":
            Self.openChat()
            result(nil)
        case "identify":
            if args.bool("firebase") == true {
                Self.activeChannel = channel
                Hailbell.identify(name: args.string("name"), email: args.string("email")) { await HailbellPlugin.firebaseIdToken() }
            } else {
                Hailbell.identify(userId: args.string("userId"), name: args.string("name"), email: args.string("email"),
                                  identityToken: args.string("identityToken"))
            }
            result(nil)
        case "setMetadata":
            Hailbell.setMetadata(args.stringMap("metadata"))
            result(nil)
        case "track":
            Hailbell.track(args.string("event") ?? "", properties: args.stringMap("properties"))
            result(nil)
        case "trackScreen":
            Hailbell.trackScreen(args.string("name") ?? "")
            result(nil)
        case "reportBug":
            Hailbell.reportBug()
            result(nil)
        case "setShakeToReport":
            Hailbell.shakeToReport = args.bool("value") ?? false
            result(nil)
        case "setPaywallPlacements":
            Hailbell.setPaywallPlacements(args.raw["placements"] as? [String] ?? [])
            result(nil)
        case "setPaywallHandler":
            if args.bool("enabled") == true {
                Self.activeChannel = channel
                Hailbell.onPaywall = { placement, purchased in HailbellPlugin.presentPaywall(placement, purchased: purchased) }
            } else {
                Hailbell.onPaywall = nil
            }
            result(nil)
        case "paywallPurchased":
            if let id = args.string("id"), let index = Self.purchases.firstIndex(where: { $0.id == id }) {
                Self.purchases.remove(at: index).purchased()
            }
            result(nil)
        case "setPushToken":
            guard let token = args.string("token"), let data = Data(hex: token) else {
                return result(FlutterError(code: "bad_token", message: "On iOS, pass the APNs token as hex (getAPNSToken()).", details: nil))
            }
            Self.setPushToken(data)
            result(nil)
        case "handleNotification":
            let data = args.raw["data"] as? [String: Any] ?? [:]
            guard data["hailbell"] != nil else { return result(false) }
            Self.openChat()
            result(true)
        case "reset":
            Hailbell.reset()
            result(nil)
        case "deleteData":
            Task { @MainActor in
                do {
                    try await Hailbell.deleteData()
                    result(nil)
                } catch {
                    result(FlutterError(code: "delete_failed", message: error.localizedDescription, details: nil))
                }
            }
        case "setDarkMode":
            Hailbell.darkMode = args.bool("value")
            result(nil)
        case "setAsksForNotifications":
            Hailbell.asksForNotifications = args.bool("value") ?? true
            result(nil)
        case "setTeamPhoto":
            Hailbell.teamPhoto = (args.raw["bytes"] as? FlutterStandardTypedData).flatMap { UIImage(data: $0.data) }
            result(nil)
        case "push.requestPermission":
            let provisional = args.bool("provisional") == true
            Task { @MainActor in result(await Hailbell.push.requestPermission(provisional: provisional)) }
        case "push.canNotify":
            Task { @MainActor in
                let status = await Hailbell.push.permission
                result(status == .authorized || status == .provisional || status == .ephemeral)
            }
        case "push.setTags":
            let tags = (args.raw["tags"] as? [String: Any] ?? [:]).mapValues { $0 as? String }
            Hailbell.push.setTags(tags)
            result(nil)
        case "push.setMarketing":
            Hailbell.push.setMarketing(args.bool("enabled") == true)
            result(nil)
        case "push.optOut":
            Hailbell.push.optOut()
            result(nil)
        case "push.handleMessage":
            let data = args.raw["data"] as? [String: Any] ?? [:]
            result(data["hailbell"] != nil || data["hb"] != nil)
        case "push.setOpenHandler":
            Self.setOpenHandler(args.bool("enabled") == true)
            result(nil)
        case "push.clearBadge":
            Hailbell.push.clearBadge(appGroup: args.string("appGroup"))
            result(nil)
        case "push.setOffersChannel":
            result(nil) // Android only
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: Unread count

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        MainActor.assumeIsolated {
            unread = Hailbell.shared.$unreadCount.removeDuplicates().sink { events($0) }
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        unread = nil
        return nil
    }

    // MARK: App delegate callbacks, forwarded by FlutterAppDelegate

    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { Self.setPushToken(deviceToken) }
    }

    /// Hailbell pushes show as a banner while the app is open. Other notifications are left to the
    /// app and its other plugins: Flutter calls every plugin, so only one may answer each.
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        guard Self.isHailbell(notification.request.content.userInfo) else { return }
        completionHandler([.banner, .list, .sound])
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
        guard Self.isHailbell(response.notification.request.content.userInfo) else { return }
        MainActor.assumeIsolated {
            if Self.configured {
                // After a launch the window needs a moment before a sheet can present.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated { Self.handleTap(response) } }
            } else {
                Self.pendingTaps.append(response)
            }
        }
        completionHandler()
    }

    // MARK: Internal

    private static func isHailbell(_ userInfo: [AnyHashable: Any]) -> Bool {
        userInfo["hailbell"] != nil || userInfo["hb"] != nil
    }

    @MainActor
    private static func handleTap(_ response: UNNotificationResponse) {
        let info = response.notification.request.content.userInfo
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier, info["hailbell"] != nil {
            openChat()
            return
        }
        Hailbell.push.handle(response)
    }

    @MainActor
    private static func handlePendingTaps() {
        guard !pendingTaps.isEmpty else { return }
        let taps = pendingTaps
        pendingTaps = []
        // Dart usually calls identify right after configure; wait for it, so the chat opens on the right person.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            MainActor.assumeIsolated { taps.forEach(handleTap) }
        }
    }

    /// The token arrives from the app delegate and, if the app passes it, from Dart too. Send it once.
    @MainActor
    private static func setPushToken(_ token: Data) {
        guard token != lastToken else { return }
        lastToken = token
        Hailbell.setPushToken(token)
    }

    /// Asks iOS for the token again when notifications are already allowed, so the token reaches
    /// Hailbell even if it was handed out before this plugin was registered. It shows no prompt.
    @MainActor
    private static func registerIfAllowed() {
        Task { @MainActor in
            let status = await Hailbell.push.permission
            if status == .authorized || status == .provisional || status == .ephemeral {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// Opens the chat. The Swift SDK applies `Hailbell.darkMode` to the sheet.
    @MainActor
    static func openChat() {
        Hailbell.shared.open()
    }

    @MainActor
    private static func setOpenHandler(_ enabled: Bool) {
        guard enabled else {
            Hailbell.push.onOpen = nil
            return
        }
        Hailbell.push.onOpen = { note in
            guard let channel = activeChannel else { return false }
            let payload: [String: Any?] = [
                "id": note.id,
                "url": note.url?.absoluteString,
                "imageUrl": note.imageURL?.absoluteString,
                "buttons": note.buttons.map { ["id": $0.id, "text": $0.text, "url": $0.url?.absoluteString as Any] },
                "data": note.data,
                "actionId": note.actionId,
            ]
            let link = note.url
            channel.invokeMethod("pushOpened", arguments: payload.compactMapValues { $0 }) { handled in
                guard (handled as? Bool) != true, let link else { return }
                MainActor.assumeIsolated { UIApplication.shared.open(link) }
            }
            return true
        }
    }

    private static func presentPaywall(_ placement: String, purchased: @escaping () -> Void) {
        guard let channel = activeChannel else { return }
        let id = UUID().uuidString
        purchases.append((id, purchased))
        if purchases.count > 20 { purchases.removeFirst(purchases.count - 20) }
        channel.invokeMethod("paywall", arguments: ["placement": placement, "id": id])
    }

    /// Asks Dart for the current Firebase ID token. Nil when Dart has none.
    private static func firebaseIdToken() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                guard let channel = activeChannel else { return continuation.resume(returning: nil) }
                channel.invokeMethod("firebaseIdToken", arguments: nil) { token in
                    continuation.resume(returning: token as? String)
                }
            }
        }
    }
}

/// The arguments of a Dart call, with Flutter's NSNull for null turned into nil.
private struct Arguments {
    let raw: [String: Any]
    init(_ raw: [String: Any]) { self.raw = raw }

    func string(_ key: String) -> String? { raw[key] as? String }
    func bool(_ key: String) -> Bool? { (raw[key] as? NSNumber)?.boolValue }
    func stringMap(_ key: String) -> [String: String] { raw[key] as? [String: String] ?? [:] }
}

private extension Data {
    /// Decodes a hex string such as an APNs token. Nil for anything that isn't hex.
    init?(hex: String) {
        guard hex.count % 2 == 0, !hex.isEmpty else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
