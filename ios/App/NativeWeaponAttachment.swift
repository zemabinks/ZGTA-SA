import simd

/// Held-model placement from the public 60662.Ko holder. This concerns the
/// folded weapon46 bag; deployed canopy/jetpack presentation remains separate.
/// These are browser attachment rules, not a verified retail runtime replay.
enum NativeWeaponAttachment {
    typealias Matrix = simd_float4x4
    static let rightHandBone = 24
    static let parachuteBone = 3

    // Ko overwrites the identity gun_para root position/rotation, below the
    // animated SPINE1 bone. Its model vertices retain their DFF-local basis.
    static var foldedParachute: Matrix {
        Matrix(columns: (SIMD4(0,0,-1,0), SIMD4(0,1,0,0),
                         SIMD4(1,0,0,0), SIMD4(0.1,-0.15,0,1)))
    }

    static func transform(weapon: Int, rightHand: Matrix?, spine: Matrix?) -> Matrix? {
        // The original holder requires R_HAND even for the spine attachment.
        guard let rightHand else { return nil }
        if weapon == 46, let spine { return spine * foldedParachute }
        // Original missing-SPINE1 fallback carries the unmodified model in
        // R_HAND; applying the back offset to that hand would be incorrect.
        return rightHand
    }

    /// Original local-player t8 effective selection. Chuting and wearing a
    /// grounded jetpack do not mean jetpackFlying; they retain their selection.
    static func selectedWeapon(_ selected: Int, swimming: Bool,
                               jetpackFlying: Bool, armWeapon: Bool) -> Int {
        !swimming && (!jetpackFlying || armWeapon) ? selected : 0
    }
}
