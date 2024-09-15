//
//  SpeechSynthesizer.swift
//  Toss Tracker
//
//  Created by Arthur Schiller on 15.09.24.
//

import Foundation
import AVFoundation
import NaturalLanguage

class SpeechSynthesizer  {
    func speakText(_ text: String) {
        guard
            let femaleVoice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.gender == .female && $0.language == "en-US" })
        else {
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = femaleVoice
        utterance.volume = 1.0  // Volume can be between 0.0 and 1.0
        utterance.rate = 0.4    // Adjust speech rate (0.5 is usually a good natural rate)
        
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.speak(utterance)
    }
}
