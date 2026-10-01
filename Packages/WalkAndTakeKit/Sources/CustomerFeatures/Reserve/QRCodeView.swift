//
//  QRCodeView.swift
//  WalkAndTakeKit
//

import DesignSystem
import Platform
import SwiftUI

/// A crisp QR image of a pickup code, for staff to scan.
struct QRCodeView: View {
    let text: String
    var size: CGFloat = 160

    var body: some View {
        Group {
            if let image = QRImageCache.image(for: text) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .padding(10)
        .background(.white, in: RoundedRectangle(cornerRadius: Radius.largeTile))
        .accessibilityLabel("QR code for pickup code \(text.map(String.init).joined(separator: " "))")
    }
}

/// Codes don't change, so each QR image is drawn once instead of on every redraw.
@MainActor
private enum QRImageCache {
    private static var images: [String: CGImage] = [:]

    static func image(for text: String) -> CGImage? {
        if let cached = images[text] { return cached }
        let image = QRCodeGenerator.image(for: text)
        images[text] = image
        return image
    }
}
