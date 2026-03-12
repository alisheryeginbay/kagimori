import SwiftUI

struct IssuerIconView: View {
    let issuer: String

    var body: some View {
        if let info = IssuerIconService.resolve(issuer) {
            Image(info.iconName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(info.brandColor)
                .frame(width: 34, height: 34)
        } else if let firstChar = issuer.first {
            Circle()
                .fill(.quaternary)
                .frame(width: 34, height: 34)
                .overlay {
                    Text(String(firstChar).uppercased())
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .foregroundStyle(.secondary)
                }
        } else {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
        }
    }
}
