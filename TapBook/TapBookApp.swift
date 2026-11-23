import SwiftData
import SwiftUI
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
struct TapBookApp: App {
    @State private var languageStore = LanguageStore()
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(languageStore)
                .task {
                    _ = await PersistenceController.shared.requestNotificationPermission()
                }
        }
        .modelContainer(PersistenceController.shared.container)
    }
}

struct MainTabView: View {
    @Environment(LanguageStore.self) private var lang

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label(lang.t("總覽", "Overview"), systemImage: "list.bullet.rectangle.portrait.fill")
                }

            AnalyticsView()
                .tabItem {
                    Label(lang.t("統計", "Analytics"), systemImage: "chart.pie.fill")
                }

            AccountsView()
                .tabItem {
                    Label(lang.t("帳戶", "Accounts"), systemImage: "creditcard.fill")
                }

            SettingsView()
                .tabItem {
                    Label(lang.t("設定", "Settings"), systemImage: "gearshape.fill")
                }
        }
        .tint(Color(hex: "#2563EB"))
    }
}
