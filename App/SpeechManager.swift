import AVFoundation // Import AVFoundation for text-to-speech


class SpeechManager: LocationUpdateDelegate {
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastSpeechDate = Date()
    @Published var maxSpeechesPerMinute: Double = 1
    
    init() {
        configureAudioSession()
    }
    
    func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Error configuring audio session: \(error)")
        }
    }
    
    // LocationUpdateDelegate method
    func didUpdateLocation(location: Location) {
        speakSpeedIfNeeded(location: location)
    }
    
    func speakSpeedIfNeeded(location: Location) {
        let now = Date()
        let maxSpeechInterval = 60.0 / maxSpeechesPerMinute
        if now.timeIntervalSince(lastSpeechDate) >= maxSpeechInterval {
            let speedInKnots = location.speed * 1.94384 // Convert from meters per second to knots
            let roundedSpeedInKnots = round(speedInKnots * 10) / 10 // Round to one decimal place
            let speech = "Speed: \(roundedSpeedInKnots) knots"
            let utterance = AVSpeechUtterance(string: speech)
            speechSynthesizer.speak(utterance)
            lastSpeechDate = now
        }
    }
}
