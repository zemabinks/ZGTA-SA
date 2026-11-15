import Foundation

/// Original42000.ur: tap an emergency horn to toggle its siren; hold250ms
/// for the horn/yelp. Each vehicle identity retains its own input boundary.
final class NativeVehicleHornController {
    struct Frame {let horn:Bool;let siren:Bool}
    private var siren=false
    private var began:Double?
    private var identity:String?
    /// Losing focus is cancellation, not a short horn tap. Keep the current
    /// siren setting but discard an incomplete gesture before releasing input.
    func cancelPress() { began=nil }
    func update(pressed:Bool,milliseconds:Double,identity:String?,emergency:Bool)->Frame {
        if identity != self.identity {self.identity=identity;siren=false;began=nil}
        guard emergency else {return Frame(horn:pressed,siren:false)}
        if pressed && began==nil {began=milliseconds}
        if !pressed,let began {
            if milliseconds-began<250 {siren.toggle()}
            self.began=nil
        }
        return Frame(horn:pressed && milliseconds-(began ?? milliseconds)>=250,siren:siren)
    }
}
