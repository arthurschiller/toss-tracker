//
//  GameView.swift
//  Toss Tracker
//
//  Created by Arthur Schiller on 15.09.24.
//

import SwiftUI

struct GamePlayingView: View {
    let viewModel: GameViewModel
    
    @State private var isScaled = false
    
    var body: some View {
        VStack {
            Text("\(viewModel.gameManager.score)")
                .contentTransition(.numericText())
                .font(.system(size: 92, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 1)
                .scaleEffect(isScaled ? 1.5 : 1.0)  // Apply the scaling effect
                .offset(y: isScaled ? 8 : 0)
                .onChange(of: viewModel.gameManager.score) { (_, newValue) in
                    isScaled = true
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if viewModel.gameManager.score == newValue {
                            isScaled = false
                        }
                    }
                }
                #if targetEnvironment(simulator)
                .onTapGesture {
                    viewModel.gameManager.debugScoreBump()
                    
                    let score = viewModel.gameManager.score
                    
                    if score > 5 {
                        viewModel.endGame(
                            data: .init(score: score, isNewHighscore: score > viewModel.gameManager.highscore)
                        )
                    }
                }
                #endif
            
            if viewModel.enableDebugging {
                Button {
                    viewModel.gameManager.reset()
                } label: {
                    Text("Reset Score")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .animation(.spring, value: isScaled)
        .animation(.spring, value: viewModel.gameManager.score)
        .padding()
    //        .glassBackgroundEffect(in: Capsule())
    }
}
