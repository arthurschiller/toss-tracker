//
//  Toss_TrackerApp.swift
//  Toss Tracker
//
//  Created by Arthur Schiller on 14.09.24.
//

import SwiftUI

@main
struct Toss_TrackerApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        #if os(visionOS)
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            VisionOSGameView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
                .preferredSurroundingsEffect(.ultraDark)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        #else
        WindowGroup {
            TestGameView()
                .environment(appModel)
        }
        #endif
     }
}
