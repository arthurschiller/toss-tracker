//
//  GameOverView.swift
//  Toss Tracker
//
//  Created by Arthur Schiller on 15.09.24.
//

import SwiftUI

struct GameOverView: View {
    let viewModel: GameViewModel
    let data: GameOverData
    
    @State private var didAppear = false
    
    var body: some View {
        
        VStack(spacing: 24) {
            Text("Game Over with \(data.score) Catches")
                .font(.system(size: 42, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 1)
                .scaleEffect(didAppear ? 1 : 0.5)
                .opacity(didAppear ? 1 : 0)
                .blur(radius: didAppear ? 0 : 12)
                .offset(y: didAppear ? 0 : 16)
            
            if data.isNewHighscore {
                ZStack {
                    Text("New Highscore! 🎉")
                        .font(.system(size: 36, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 1)
                        .scaleEffect(didAppear ? 1 : 0.5)
                        .opacity(didAppear ? 1 : 0)
                        .blur(radius: didAppear ? 0 : 12)
                        .offset(y: didAppear ? 0 : 16)
                }
                .animation(.spring(duration: 1.2).delay(0.5), value: didAppear)
            }
        }
        .animation(.spring(duration: 1.2), value: didAppear)
        .onAppear {
            didAppear = true
        }
    }
}
