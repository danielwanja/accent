import SwiftUI
import UIKit

extension UIColor {
    convenience init(light: UInt32, dark: UInt32) {
        self.init { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
        }
    }
}

// Warm paper, cool ink, record red, and practice amber.
enum Theme {
    static let paper = Color(uiColor: UIColor(light: 0xFBFBF8, dark: 0x17191E))
    static let surface = Color(uiColor: UIColor(light: 0xF3F3EE, dark: 0x1F2229))
    static let ink = Color(uiColor: UIColor(light: 0x22262C, dark: 0xE7E7E2))
    static let muted = Color(uiColor: UIColor(light: 0x6A7078, dark: 0x9BA1A9))
    static let line = Color(uiColor: UIColor(light: 0xE2E2DA, dark: 0x30343C))
    static let accent = Color(uiColor: UIColor(light: 0xC24A3E, dark: 0xE06A5C))
    static let amberWash = Color(uiColor: UIColor(light: 0xF5E7C7, dark: 0x453B1C))
    static let amber = Color(uiColor: UIColor(light: 0xC08A28, dark: 0xD9A054))
    static let upcoming = Color(uiColor: UIColor(light: 0xABB0B6, dark: 0x5C626B))
}
