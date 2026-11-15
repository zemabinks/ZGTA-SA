import AVFoundation
import Foundation

/// Actual owner-supplied frontend sounds. No substitute sample is generated
/// when the optional private resource is missing or cannot be decoded.
final class NativeMenuAudio:NSObject,AVAudioPlayerDelegate {
    enum Sound:String {case start,back,highlight,tab}
    static let shared=NativeMenuAudio()
    private var players:[ObjectIdentifier:AVAudioPlayer]=[:]
    private var bytes:[Sound:Data]=[:]
    private var gain:Float=0.7
    private var observer:NSObjectProtocol?
    private override init() {
        super.init()
        applySettings(NativeAppSettings.shared.snapshot)
        observer=NotificationCenter.default.addObserver(forName:NativeAppSettings.didChange,object:nil,queue:.main){[weak self] note in
            guard let store=note.object as? NativeAppSettings else{return}
            self?.applySettings(store.snapshot)
        }
    }
    deinit {if let observer{NotificationCenter.default.removeObserver(observer)}}
    func applySettings(_ snapshot:NativeAppSettings.Snapshot) {
        gain=snapshot.validated().effectiveEffectsGain
        for player in players.values {player.volume=gain}
    }
    func play(_ sound:Sound) {
        let data:Data
        if let cached=bytes[sound] {data=cached}
        else {
            guard let url=NativeDEMenuAssets.shared.soundURL(key:sound.rawValue),
                  let original=try? Data(contentsOf:url),let prepared=NativeMenuSoundData.playableWave(original) else{return}
            bytes[sound]=prepared;data=prepared
        }
        guard let player=try? AVAudioPlayer(data:data) else{return}
        player.volume=gain;player.delegate=self
        players[ObjectIdentifier(player)]=player
        if !player.play(){players.removeValue(forKey:ObjectIdentifier(player))}
        if players.count>12,let old=players.first {old.value.stop();players.removeValue(forKey:old.key)}
    }
    func audioPlayerDidFinishPlaying(_ player:AVAudioPlayer,successfully flag:Bool) {
        players.removeValue(forKey:ObjectIdentifier(player))
    }
}
