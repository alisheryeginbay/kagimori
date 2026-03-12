import SwiftUI

struct CodeCardView: View {
    let account: OTPAccount
    let date: Date
    var isCopied: Bool = false

    private var code: String {
        guard let secret = KeychainService.retrieve(for: account.keychainKey) else {
            return String(repeating: "\u{2013}", count: account.digits)
        }
        return TOTPGenerator.generate(
            secret: secret,
            algorithm: account.algorithm,
            digits: account.digits,
            period: account.period,
            date: date
        )
    }

    private var timeRemaining: Int {
        TOTPGenerator.timeRemaining(period: account.period, date: date)
    }

    private var progress: Double {
        Double(timeRemaining) / Double(account.period)
    }

    private var formattedCode: String {
        let mid = code.count / 2
        return "\(code.prefix(mid)) \(code.suffix(code.count - mid))"
    }

    var body: some View {
        HStack(spacing: 16) {
            IssuerIconView(issuer: account.issuer)

            VStack(alignment: .leading, spacing: 4) {
                Text(account.issuer)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(formattedCode)
                    .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                    .contentTransition(.numericText())
                    .animation(.default, value: code)

                if !account.accountName.isEmpty {
                    Text(account.accountName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isCopied {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                countdownRing
            }
        }
        .padding()
        .contentShape(.rect)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }

    private var countdownRing: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 3)
                .opacity(0.15)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .foregroundStyle(timeRemaining > 5 ? Color.primary : Color.red)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: timeRemaining)

            Text("\(timeRemaining)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .frame(width: 40, height: 40)
    }
}
