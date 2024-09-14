//
//  PreGameView.swift
//  Toss Tracker
//
//  Created by Arthur Schiller on 14.09.24.
//

import SwiftUI

struct PreGameView: View {
    let viewModel: GameViewModel
    
    @State private var amount: Double = 1
    @State private var didAppear = false
    
    var body: some View {
//        VStack {
//            Text("Leaderboard")
//            
////            Button("Add Ball") {
////                viewModel.addBall()
////            }
//        }
//        .padding()
//        .frame(minWidth: 320)
//        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 24))
//        .padding(.top, 200)
//        .overlay(alignment: .bottom) {
//            logoView
//        }
        
        logoView
    }
    
    @ViewBuilder
    var logoView: some View {
        VStack {
            Text(attributedTossTracker)
                .font(.system(size: 64, design: .rounded))
//                    .kerning(didAppear ? 0.05 : 0)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 1)
                .frame(width: 400, height: 200)
                .textRenderer(LogoTextRenderer(strength: amount, frequency: 0.5))
                .onAppear {
                    withAnimation(.easeInOut(duration: 3)) {
                        amount = 0
                    }
                }
        }
        .offset(y: -50)
        .frame(depth: 0.5)
        .scaleEffect(didAppear ? 0.95 : 1.0)
        .opacity(didAppear ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: didAppear)
        .onAppear {
            didAppear = true
        }
    }
    
    var attributedTossTracker: AttributedString {
        var attributedString = AttributedString("Toss Tracker")
        
        // Apply regular font to "Toss"
        if let range = attributedString.range(of: "Toss") {
            attributedString[range].font = .system(size: 64, weight: .heavy, design: .rounded)
        }
        
        // Apply bold font to "Tracker"
        if let range = attributedString.range(of: "Tracker") {
            attributedString[range].font = .system(size: 64, weight: .light, design: .rounded)
        }
        
        return attributedString
    }
}

struct LogoTextRenderer: TextRenderer {
    var strength: Double
    var frequency: Double

    var animatableData: Double {
        get { strength }
        set { strength = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let stepDelay: TimeInterval = 0.15
        for line in layout {
            for run in line {
                for (index, glyph) in run.enumerated() {
                    let glyphEffectStrength = strength - (stepDelay * Double(index) / Double(run.count))
                    let offsetValue = 10 * glyphEffectStrength
                    let yOffset = offsetValue * sin(Double(index) * frequency)
                    var copy = context

                    copy.translateBy(x: 0, y: yOffset)
                    copy.addFilter(.blur(radius: 10 * glyphEffectStrength))
                    copy.opacity = 1 - (0.5 * glyphEffectStrength)
                    copy.draw(glyph, options: .disablesSubpixelQuantization)
                }
            }
        }
    }
}

struct AnimatingMeshView: View {
    let referenceDate: Date
    
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(referenceDate)
            
            MeshGradient(width: 5, height: 4, points: [
                [0, 0], [0.25, 0], [0.5, 0], [0.75, 0], [1, 0],
                
                [0, 0.333],
                [value(in: 0.0...0.2, offset: 0.1, timeScale: 0.2, t: t),   value(in: 0.25...0.4, offset: 0.1, timeScale: 0.3, t: t)],
                [value(in: 0.4...0.6, offset: 0.05, timeScale: 0.3, t: t),  value(in: 0.2...0.4, offset: 0.15, timeScale: 0.3, t: t)],
                [value(in: 0.8...1.0, offset: 0.1, timeScale: 0.3, t: t),   value(in: 0.15...0.3, offset: 0.1, timeScale: 0.4, t: t)],
                [1, 0.333],
                
                [0, 0.667],
                [value(in: 0.2...0.3, offset: 0.05, timeScale: 0.3, t: t),  value(in: 0.6...0.95, offset: 0.1, timeScale: 0.4, t: t)],
                [value(in: 0.4...0.6, offset: 0.07, timeScale: 0.25, t: t),  value(in: 0.6...0.9, offset: 0.1, timeScale: 0.3, t: t)],
                [value(in: 0.8...0.9, offset: 0.06, timeScale: 0.3, t: t),  value(in: 0.6...0.8, offset: 0.12, timeScale: 0.3, t: t)],
                [1, 0.667],
                
                [0, 1], [0.25, 1], [0.5, 1], [0.75, 1], [1, 1],
            ], colors: [
                .black, .black, .black, .black, .black,
                .black, .green, .yellow, .orange, .black,
                .black, .blue, .purple, .red, .black,
                .black, .black, .black, .black, .black
            ])
        }
    }
    
    func value(in range: ClosedRange<Float>, offset: Float, timeScale: Float, t: TimeInterval) -> Float {
        let amp = (range.upperBound - range.lowerBound) * 0.5
        let midPoint = (range.lowerBound + range.upperBound) * 0.5
        return midPoint + amp * sin(timeScale * Float(t) + offset)
    }
}
