import SwiftUI

enum IssuerIconService {
    struct IssuerInfo {
        let iconName: String
        let brandColor: Color
    }

    private static let darkHexValues: Set<String> = [
        "000000", "181717", "313131", "1a1a1a", "151515",
    ]

    private static let lightHexValues: Set<String> = [
        "FFFC00", "F0B90B",
    ]

    private static let registry: [String: (icon: String, hex: String)] = [
        "google": ("google", "4285F4"),
        "github": ("github", "181717"),
        "microsoft": ("microsoft", "5E5E5E"),
        "amazon": ("amazon", "FF9900"),
        "apple": ("apple", "000000"),
        "facebook": ("facebook", "0866FF"),
        "x": ("x", "000000"),
        "twitter": ("x", "000000"),
        "discord": ("discord", "5865F2"),
        "slack": ("slack", "4A154B"),
        "dropbox": ("dropbox", "0061FF"),
        "reddit": ("reddit", "FF4500"),
        "linkedin": ("linkedin", "0A66C2"),
        "twitch": ("twitch", "9146FF"),
        "steam": ("steam", "000000"),
        "epicgames": ("epicgames", "313131"),
        "epic games": ("epicgames", "313131"),
        "coinbase": ("coinbase", "0052FF"),
        "binance": ("binance", "F0B90B"),
        "paypal": ("paypal", "003087"),
        "stripe": ("stripe", "635BFF"),
        "cloudflare": ("cloudflare", "F38020"),
        "aws": ("amazonwebservices", "232F3E"),
        "amazonwebservices": ("amazonwebservices", "232F3E"),
        "amazon web services": ("amazonwebservices", "232F3E"),
        "digitalocean": ("digitalocean", "0080FF"),
        "digital ocean": ("digitalocean", "0080FF"),
        "gitlab": ("gitlab", "FC6D26"),
        "bitbucket": ("bitbucket", "0052CC"),
        "npm": ("npm", "CB3837"),
        "pypi": ("pypi", "3775A9"),
        "docker": ("docker", "2496ED"),
        "heroku": ("heroku", "430098"),
        "vercel": ("vercel", "000000"),
        "netlify": ("netlify", "00C7B7"),
        "notion": ("notion", "000000"),
        "1password": ("1password", "3B66BC"),
        "bitwarden": ("bitwarden", "175DDC"),
        "protonmail": ("protonmail", "6D4AFF"),
        "proton mail": ("protonmail", "6D4AFF"),
        "proton": ("protonmail", "6D4AFF"),
        "tutanota": ("tutanota", "840010"),
        "tuta": ("tutanota", "840010"),
        "figma": ("figma", "F24E1E"),
        "adobe": ("adobe", "FF0000"),
        "snapchat": ("snapchat", "FFFC00"),
        "snap": ("snapchat", "FFFC00"),
        "2fas": ("2fas", "EC1C24"),
        "meta": ("facebook", "0866FF"),
    ]

    static func resolve(_ issuer: String) -> IssuerInfo? {
        let normalized = normalize(issuer)
        guard let entry = registry[normalized] else { return nil }
        let color: Color
        if darkHexValues.contains(entry.hex) || lightHexValues.contains(entry.hex) {
            color = .primary
        } else {
            color = Color(hex: entry.hex)
        }
        return IssuerInfo(iconName: entry.icon, brandColor: color)
    }

    private static func normalize(_ issuer: String) -> String {
        issuer
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",? *(inc\\.?|llc|ltd|corp\\.?)$", with: "", options: .regularExpression)
            .replacingOccurrences(of: ".", with: "")
    }
}

private extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
