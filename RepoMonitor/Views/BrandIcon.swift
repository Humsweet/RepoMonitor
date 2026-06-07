import SwiftUI
import AppKit

/// The app's brand mark — the lucide "folder-git-2" glyph.
///
/// Loads `AppGlyph` (a white template PNG shipped in the bundle's Resources by
/// `scripts/bundle.sh`) so it can be tinted to any color. Falls back to an SF
/// Symbol when the resource is absent (e.g. plain `swift build` dev runs that
/// don't package Resources).
struct BrandIcon: View {
    var size: CGFloat = 18
    var color: Color = Theme.accent

    var body: some View {
        Group {
            if let image = Self.templateImage {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
            } else {
                Image(systemName: "folder.badge.gearshape")
                    .resizable()
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .foregroundStyle(color)
    }

    private static let templateImage: NSImage? = {
        guard let image = NSImage(named: "AppGlyph") else { return nil }
        image.isTemplate = true
        return image
    }()
}
