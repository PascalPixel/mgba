import Foundation

enum ShaderPreset: String, CaseIterable, Identifiable {
    case native = "builtin.native"
    case colorCorrected = "builtin.color-corrected"
    case lcdGrid = "builtin.lcd-grid"
    case softLCD = "builtin.soft-lcd"
    case classicGreen = "builtin.classic-green"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .native: "Native Pixels"
        case .colorCorrected: "GBA Color"
        case .lcdGrid: "LCD Grid"
        case .softLCD: "Soft LCD"
        case .classicGreen: "Classic Green"
        }
    }

    var detail: String {
        switch self {
        case .native:
            "Exact emulator output with your nearest or smooth filtering preference."
        case .colorCorrected:
            "Tames saturation and contrast for a look closer to the original GBA screen."
        case .lcdGrid:
            "Adds a crisp source-pixel grid without changing the game’s palette."
        case .softLCD:
            "Blends pixels gently with subtle scanlines for a softer handheld display."
        case .classicGreen:
            "Maps luminance to a four-tone green palette inspired by the original Game Boy."
        }
    }

    var systemImage: String {
        switch self {
        case .native: "square.grid.3x3"
        case .colorCorrected: "paintpalette"
        case .lcdGrid: "grid"
        case .softLCD: "display"
        case .classicGreen: "leaf"
        }
    }

    var fragmentFunctionName: String {
        switch self {
        case .native: "mgba_nearest"
        case .colorCorrected: "mgba_color_corrected"
        case .lcdGrid: "mgba_lcd_grid"
        case .softLCD: "mgba_soft_lcd"
        case .classicGreen: "mgba_classic_green"
        }
    }
}
