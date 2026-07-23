import SwiftUI

enum LabTheme {
    // Authored in OKLCH, then converted to the extended sRGB values SwiftUI consumes.
    // Chroma stays restrained so status colors remain legible without decorating the UI.
    static let signal = Color(red: 0.194, green: 0.544, blue: 0.505) // oklch(58% 0.085 185)
    static let inbound = Color(red: 0.165, green: 0.490, blue: 0.580) // oklch(55% 0.085 220)
    static let draft = Color(red: 0.686, green: 0.455, blue: 0.255) // oklch(61% 0.10 60)
    static let verified = Color(red: 0.289, green: 0.520, blue: 0.300) // oklch(56% 0.105 145)
    static let danger = Color(red: 0.731, green: 0.295, blue: 0.279) // oklch(56% 0.145 25)
    static let chartChord = Color(red: 0.945, green: 0.580, blue: 0.311) // oklch(75% 0.14 55)

    static let stageBackground = Color(red: 0.055, green: 0.082, blue: 0.078)
    static let stageSurface = Color(red: 0.098, green: 0.129, blue: 0.122)
    static let annotation = Color(red: 0.939, green: 0.806, blue: 0.437)
    static let annotationInk = Color(red: 0.105, green: 0.095, blue: 0.066)

    static let radius: CGFloat = 7
    static let control: CGFloat = 12
    static let standard: CGFloat = 16
    static let page: CGFloat = 24
    static let section: CGFloat = 28
    static let statusStripHeight: CGFloat = 56
}
