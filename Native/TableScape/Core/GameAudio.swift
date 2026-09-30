import Foundation
import AVFoundation

/// Original gateway audio is fetched on demand. No audio is written to the simulator disk.
@MainActor
final class GameAudio {
    private weak var session: GameSession?
    private var generation = 0
    private var currentMusic = -2
    private var musicRequest = 0
    private var music: AVAudioPlayer?
    private var jingle: AVAudioPlayer?
    private var sounds: [AVAudioPlayer] = []
    private var seen = Set<Int>()
    private var history: [Int] = []
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var musicSetting = 0
    private var soundSetting = 0

    init(session: GameSession) { self.session = session }
    private var musicVolume: Float { Float(session?.musicVolume ?? 0.45) * (musicSetting >= 4 ? 0 : pow(10, -Float(musicSetting) * 4 / 20)) }
    private var soundVolume: Float { Float(session?.soundVolume ?? 0.7) * (soundSetting >= 4 ? 0 : pow(10, -Float(soundSetting) * 4 / 20)) }

    func update(_ state: JSONObject) {
        if session?.audioEnabled == false { if currentMusic != -2 { reset() }; return }
        musicSetting = state.int("musicSetting"); soundSetting = state.int("soundSetting")
        music?.volume = musicVolume; jingle?.volume = musicVolume
        sounds.removeAll { !$0.isPlaying }
        sounds.forEach { $0.volume = soundVolume }
        let song = state.object("music")
        if !song.isEmpty, song.int("id", -1) != currentMusic {
            currentMusic = song.int("id", -1)
            musicRequest += 1
            if currentMusic < 0 { music?.stop(); music = nil }
            else { loadMusic(currentMusic, request: musicRequest) }
        }
        for event in state.objects("audio") {
            let id = event.int("event")
            guard seen.insert(id).inserted else { continue }
            history.append(id)
            while history.count > 512 { seen.remove(history.removeFirst()) }
            play(event, currentTick: state.int("tick"))
        }
    }
    private func start(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        tasks[id] = Task { [weak self] in
            await operation()
            self?.tasks.removeValue(forKey: id)
        }
    }
    private func loadMusic(_ id: Int, request: Int) {
        let epoch = generation
        start { [weak self] in
            guard let self, let session = self.session else { return }
            do {
                let data = try await session.data(path: "/v1/audio/music/\(id)?loops=1")
                guard self.generation == epoch, self.musicRequest == request, !Task.isCancelled else { return }
                let player = try AVAudioPlayer(data: data)
                player.numberOfLoops = -1; player.volume = self.musicVolume
                player.prepareToPlay()
                self.music?.stop(); self.music = player
                if self.jingle?.isPlaying != true { player.play() }
                print("SCAPE_NATIVE_MUSIC id=\(id) duration=\(player.duration)")
            } catch { if self.generation == epoch, !Task.isCancelled { print("SCAPE_NATIVE_AUDIO_UNAVAILABLE music=\(id)") } }
        }
    }
    private func play(_ event: JSONObject, currentTick: Int) {
        let epoch = generation
        let due = Date().addingTimeInterval(event.double("delay") - Double(max(0, currentTick - event.int("tick"))) * 0.6)
        let kind = event.string("kind"), id = event.int("id"), loops = min(8, max(1, event.int("loops", 1)))
        guard tasks.count < 24, id >= 0 else { return }
        start { [weak self] in
            guard let self, let session = self.session else { return }
            do {
                let data = try await session.data(path: "/v1/audio/\(kind == "sound" ? "sound" : "music")/\(id)?loops=\(loops)")
                guard self.generation == epoch, !Task.isCancelled else { return }
                let player = try AVAudioPlayer(data: data)
                let remaining = due.timeIntervalSinceNow
                if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                guard self.generation == epoch, !Task.isCancelled else { return }
                if kind == "jingle" {
                    self.music?.pause(); self.jingle?.stop(); self.jingle = player
                    player.volume = self.musicVolume; player.play()
                    try await Task.sleep(nanoseconds: UInt64(max(player.duration, event.double("resumeAfter")) * 1_000_000_000))
                    if self.generation == epoch, self.jingle === player { self.jingle = nil; self.music?.play() }
                } else if -due.timeIntervalSinceNow <= player.duration + 1 {
                    player.volume = self.soundVolume
                    if self.sounds.count >= 16 { self.sounds.removeFirst().stop() }
                    self.sounds.append(player); player.play()
                }
            } catch { if self.generation == epoch, !Task.isCancelled { print("SCAPE_NATIVE_AUDIO_UNAVAILABLE kind=\(kind) id=\(id)") } }
        }
    }
    func reset() {
        generation += 1; musicRequest += 1
        tasks.values.forEach { $0.cancel() }; tasks.removeAll()
        music?.stop(); jingle?.stop(); sounds.forEach { $0.stop() }
        music = nil; jingle = nil; sounds.removeAll(); seen.removeAll(); history.removeAll(); currentMusic = -2
    }
}
