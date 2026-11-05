import AppKit
import SwiftUI

enum Glyph: String {
    case menubar
    case tabResources = "tab-resources"
    case tabProcesses = "tab-processes"
    case tabApps = "tab-apps"

    /// swift runなど、バンドルに画像がない起動方法のときに使う。
    private var fallbackSymbolName: String {
        switch self {
        case .menubar: return "gauge.with.dots.needle.67percent"
        case .tabResources: return "gauge.with.needle"
        case .tabProcesses: return "list.bullet"
        case .tabApps: return "square.grid.2x2.fill"
        }
    }

    var image: Image {
        guard let image = Bundle.main.image(forResource: rawValue) else {
            return Image(systemName: fallbackSymbolName)
        }
        // テンプレートにすると、ライトとダークでシステムが色を合わせる。
        image.isTemplate = true
        return Image(nsImage: image)
    }
}
