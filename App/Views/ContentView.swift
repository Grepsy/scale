import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            TabView {
                WeighView()
                HistoryView()
                SettingsView()
            }
            .tabViewStyle(.verticalPage)
        }
    }
}
