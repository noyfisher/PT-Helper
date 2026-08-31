import SwiftUI
import UIKit

// MARK: - Notifications

extension Notification.Name {
    static let popToRoot = Notification.Name("popToRoot")
    static let deepLink = Notification.Name("deepLink")
}

// MARK: - COIL Design Tokens
// Two-tier adaptive color system (light + dark).
// Tier 0 `CoilPalette` holds the raw hues — the ONLY place RGB lives — and is shared by
// both AppColors (SwiftUI) and Models/BodyMapConstants (UIKit/RealityKit).
// Tier 1 `AppColors` maps semantic roles onto Tier 0; token names are preserved so
// component/screen code needs no changes. Headings use Industry-Bold; body uses Inter
// (registered in Info.plist under UIAppFonts).

enum CoilPalette {
    /// Build a light/dark adaptive UIColor from two fixed hues.
    static func dyn(_ light: UIColor, _ dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }
    /// 0xRRGGBB → opaque UIColor.
    static func hex(_ v: Int) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255.0,
                green: CGFloat((v >> 8) & 0xFF) / 255.0,
                blue: CGFloat(v & 0xFF) / 255.0, alpha: 1.0)
    }

    // Brand — teal ("Coiled energy")
    static let accent       = dyn(hex(0x0FB5B0), hex(0x2CC7C2))
    static let accentDeep   = dyn(hex(0x0B7A78), hex(0x17A6A2)) // CTA / text on white
    static let accentBright = dyn(hex(0x3FD0CB), hex(0x5FE0DB))
    static let accentDeeper = dyn(hex(0x075E5C), hex(0x0B7A78))

    // Ink / chrome — fixed dark in BOTH modes (nav bar, tab bar, hero surfaces)
    static let ink         = hex(0x0E1C22)
    static let inkElevated = hex(0x16303A)
    static let inkDeep     = hex(0x0B1418)

    // Neutral surfaces
    static let page     = dyn(hex(0xF3F5F4), hex(0x0E1518))
    static let card     = dyn(hex(0xFFFFFF), hex(0x16232A))
    static let elevated = dyn(hex(0xF5F7F6), hex(0x1C2A31))
    static let inputBg  = dyn(hex(0xF8FAF9), hex(0x111D22))

    // Text
    static let textPrimary   = dyn(hex(0x111A1D), hex(0xEAF2F1))
    static let textSecondary = dyn(hex(0x4B5A5E), hex(0x9DB2B3))
    static let textMuted     = dyn(hex(0x7A8A8D), hex(0x6E8285))

    // Semantics — decoupled from the brand hue
    // Both variants darkened for AA against the FIXED-white `ctaText` they are
    // always paired with: dark was #F0736E at 2.84:1 (badly failing on the
    // red-flag safety notice, offline banner and emergency screens) and light
    // was #D64541 at 4.39:1, marginally under. Now 4.93:1 and 4.80:1, and both
    // still read clearly as an alert against their page (4.50:1 / 3.84:1).
    // Hue-preserving and strictly higher contrast, so the ~66 danger call sites
    // change only in that direction.
    static let errorRed = dyn(hex(0xC93F3B), hex(0xCB4238))
    static let success  = dyn(hex(0x1E874B), hex(0x3FBE77))
    static let warning  = dyn(hex(0xC67A00), hex(0xE8A73B))
    static let infoBlue = dyn(hex(0x2E74C7), hex(0x5DA0E8))
    static let pop      = dyn(hex(0xF5A623), hex(0xFBC15A)) // streaks / achievements

    // Hairline (adaptive black/white alpha)
    static let hairline = dyn(UIColor.black.withAlphaComponent(0.08),
                              UIColor.white.withAlphaComponent(0.10))
}

enum AppColors {
    // MARK: Brand
    static let accent  = Color(CoilPalette.accent)
    static let success = Color(CoilPalette.success)
    static let warning = Color(CoilPalette.warning)
    static let danger  = Color(CoilPalette.errorRed)   // decoupled from brand
    static let info    = Color(CoilPalette.infoBlue)   // decoupled from brand

    // MARK: Text
    static let primaryText    = Color(CoilPalette.textPrimary)
    static let secondaryText  = Color(CoilPalette.textSecondary)
    static let mutedText      = Color(CoilPalette.textMuted)
    static let textOnDark      = Color.white
    static let textOnDarkMuted = Color.white.opacity(0.6)
    /// On-color for the FIXED teal surfaces (coolGradient / healingGradient /
    /// accent fills). Those gradients stay teal in both appearances, so their
    /// on-color must be fixed too. It is near-black rather than white because
    /// the brand teal is light: white lands at 1.6–2.5:1 on the bright stops
    /// while this reads 6.9–11.1:1.
    static let textOnAccent      = Color(CoilPalette.inkDeep)
    static let textOnAccentMuted = Color(CoilPalette.inkDeep).opacity(0.75)

    // MARK: Surfaces
    static let cardBackground  = Color(CoilPalette.card)
    static let pageBackground  = Color(CoilPalette.page)
    static let elevatedSurface = Color(CoilPalette.elevated)
    static let inputBackground = Color(CoilPalette.inputBg)
    static let subtleBorder    = Color(CoilPalette.hairline)

    // MARK: Dark surfaces (nav bar, hero cards, workout screen — fixed dark both modes)
    static let darkSurface         = Color(CoilPalette.ink)
    static let darkSurfaceElevated = Color(CoilPalette.inkElevated)
    static let navBackground       = Color(CoilPalette.ink)
    static let navBorder           = Color.white.opacity(0.08)

    // MARK: Tab bar
    static let tabActive   = Color(CoilPalette.accent)
    static let tabInactive = Color.white.opacity(0.45)

    // MARK: CTA
    static let ctaBackground = Color(CoilPalette.accentDeep)
    static let ctaText       = Color.white

    // MARK: Accent variants
    static let accentLight = Color(CoilPalette.accentBright)
    static let accentDark  = Color(CoilPalette.accentDeeper)
    static let accentTint  = Color(CoilPalette.accent).opacity(0.10)
    static let accentText = Color(CoilPalette.accentDeep)  // AA text: 5.16:1 on white, 5.7:1 on dark cards

    // MARK: Chip
    static let chipSelectedBg     = Color(CoilPalette.accentDeeper)
    static let chipSelectedBorder = Color(CoilPalette.accentDeeper)
    static let chipSelectedText   = Color.white

    // MARK: Card styling
    static let cardBorder      = Color(CoilPalette.hairline)
    static let cardShadowColor = Color.black.opacity(0.06)
    static let inputFocusBorder = Color(CoilPalette.accent)

    // MARK: Gradients
    static let primaryGradient = LinearGradient(
        colors: [Color(CoilPalette.accent), Color(CoilPalette.accentDeep)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let warmGradient = LinearGradient(
        colors: [Color(CoilPalette.pop), Color(CoilPalette.warning)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let coolGradient = LinearGradient(
        colors: [Color(CoilPalette.accent), Color(CoilPalette.accentBright)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let healingGradient = LinearGradient(
        colors: [Color(CoilPalette.accent), Color(CoilPalette.accentDeep)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    // Login / launch / hero background — fixed dark in both modes
    static let bgGradient = LinearGradient(
        colors: [Color(CoilPalette.inkDeep), Color(CoilPalette.ink)],
        startPoint: .top, endPoint: .bottom
    )

    // MARK: Dashboard aliases (backward-compat — existing Dashboard views keep compiling)
    static let dashBackground       = pageBackground
    static let dashSurface          = cardBackground
    static let dashAccent           = accent
    static let dashSecondaryAccent  = accentLight
    static let dashBorder           = cardBorder
    static let dashTextPrimary      = primaryText
    static let dashTextSecondary    = secondaryText
    static let dashSuccess          = success
    static let dashWarning          = warning
    static let dashDanger           = danger
    static let dashAccentGradient   = primaryGradient
}

// MARK: - Appearance Preference

/// User-selectable app appearance (System / Light / Dark). Persisted via
/// `@AppStorage(AppAppearance.storageKey)` and applied at the app root.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
    static let storageKey = "coil.appearance"
}

// MARK: - COIL Brandmark

/// The COIL brandmark glyph — a spring seen side-on (overlapping rings) in the brand teal.
/// The whole ring group is sized from the frame HEIGHT and centered, so it reads
/// consistently whether the frame is square or wide.
struct CoilGlyph: View {
    var color: Color = AppColors.accent
    var rings: Int = 4

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let lw = max(1.4, h * 0.10)
            let ry = h * 0.45
            let rx = h * 0.13
            let spacing = rx * 1.55
            let groupW = rx * 2 + spacing * CGFloat(max(rings - 1, 0))
            let startCX = (w - groupW) / 2 + rx
            Path { p in
                for i in 0..<rings {
                    let cx = startCX + spacing * CGFloat(i)
                    p.addEllipse(in: CGRect(x: cx - rx, y: h / 2 - ry, width: rx * 2, height: ry * 2))
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

/// COIL wordmark — spring-rings glyph + letter-spaced wordmark. Used in nav bars and hero screens.
struct CoilWordmark: View {
    var fontSize: CGFloat = 18
    var glyph: CGFloat = 22
    var textColor: Color = .white

    var body: some View {
        HStack(spacing: 8) {
            CoilGlyph()
                .frame(width: glyph * 1.2, height: glyph)
            Text("COIL")
                .font(Font.custom("Industry-Bold", size: fontSize))
                .tracking(fontSize * 0.22)
                .foregroundColor(textColor)
        }
        .accessibilityElement()
        .accessibilityLabel("COIL")
    }
}

// MARK: - Spacing

enum AppSpacing {
    static let nano: CGFloat = 2
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 12
    static let lg:   CGFloat = 16
    static let xl:   CGFloat = 20
    static let xxl:  CGFloat = 28
    static let xxxl: CGFloat = 40

    // Aliases for commonly needed in-between values
    static let tight:       CGFloat = 6
    static let comfortable: CGFloat = 10
    static let wide:        CGFloat = 24
    static let huge:        CGFloat = 32
}

// MARK: - Corner Radii

enum AppCorners {
    static let small:  CGFloat = 8    // chips, small buttons
    static let medium: CGFloat = 12   // inputs, smaller cards
    static let card:   CGFloat = 16   // standard cards
    static let large:  CGFloat = 20   // large cards
    static let xl:     CGFloat = 24   // hero cards
    static let xxl:    CGFloat = 28
    static let pill:   CGFloat = 100  // capsule buttons
}

// MARK: - Typography
// Industry Bold for headings; Inter (Regular/Medium/SemiBold) for body.
// Custom font files must be added to Xcode and registered in Info.plist under UIAppFonts.

enum AppFonts {
    // MARK: Headings — Industry Bold
    // `relativeTo:` makes every custom token scale with the iOS "Larger Text"
    // setting (audit #65). The point sizes are unchanged at the default Dynamic
    // Type size; they now grow/shrink proportionally to the mapped text style.
    static let display      = Font.custom("Industry-Bold", size: 36, relativeTo: .largeTitle) // large stat/hero number
    static let heroTitle    = Font.custom("Industry-Bold", size: 28, relativeTo: .title)
    static let title        = Font.custom("Industry-Bold", size: 24, relativeTo: .title2)
    static let sectionTitle = Font.custom("Industry-Bold", size: 20, relativeTo: .title3)
    static let cardTitle    = Font.custom("Industry-Bold", size: 14, relativeTo: .headline)
    static let statNumber   = Font.custom("Industry-Bold", size: 28, relativeTo: .title)
    static let badge        = Font.custom("Industry-Bold", size: 10, relativeTo: .caption2)
    static let fieldLabel   = Font.custom("Industry-Bold", size: 11, relativeTo: .caption2) // uppercase field labels

    // MARK: Body — Inter
    static let body         = Font.custom("Inter-Regular",  size: 14, relativeTo: .body)
    static let bodyMedium   = Font.custom("Inter-Medium",   size: 14, relativeTo: .body)
    static let bodySemiBold = Font.custom("Inter-SemiBold", size: 14, relativeTo: .body)

    // MARK: Small — Inter 13pt
    static let small         = Font.custom("Inter-Regular",  size: 13, relativeTo: .subheadline)
    static let smallMedium   = Font.custom("Inter-Medium",   size: 13, relativeTo: .subheadline)
    static let smallSemiBold = Font.custom("Inter-SemiBold", size: 13, relativeTo: .subheadline)

    // MARK: Caption — Inter 12pt
    static let caption         = Font.custom("Inter-Regular",  size: 12, relativeTo: .caption)
    static let captionMedium   = Font.custom("Inter-Medium",   size: 12, relativeTo: .caption)
    static let captionSemiBold = Font.custom("Inter-SemiBold", size: 12, relativeTo: .caption)

    // MARK: Micro — Inter 11pt
    static let micro       = Font.custom("Inter-Regular",  size: 11, relativeTo: .caption2)
    static let microMedium = Font.custom("Inter-Medium",   size: 11, relativeTo: .caption2)

    // MARK: Dashboard data (monospaced for number alignment)
    static let dataLarge  = Font.system(.title,    design: .monospaced).weight(.bold)
    static let dataMedium = Font.system(.body,     design: .monospaced).weight(.semibold)
    static let dataSmall  = Font.system(.footnote, design: .monospaced).weight(.medium)
    static let dashLabel  = Font.system(.caption2).weight(.semibold)
}

// MARK: - Animation Presets

enum AppAnimations {
    static let springy = Animation.spring(response: 0.35, dampingFraction: 0.7)
    static let smooth  = Animation.easeInOut(duration: 0.25)
    static let bouncy  = Animation.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0.1)
    static let press   = Animation.spring(response: 0.12)
}

// MARK: - Card Style

struct CardStyle: ViewModifier {
    enum Elevation { case flat, subtle, raised, hero }
    var elevation: Elevation = .subtle

    func body(content: Content) -> some View {
        content
            .padding(AppSpacing.lg)
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.card)
            .overlay(
                RoundedRectangle(cornerRadius: AppCorners.card)
                    .stroke(AppColors.cardBorder, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
    }

    private var shadowColor: Color {
        elevation == .hero ? Color.black.opacity(0.18) : AppColors.cardShadowColor
    }
    private var shadowRadius: CGFloat {
        switch elevation {
        case .flat: return 0; case .subtle: return 8
        case .raised: return 12; case .hero: return 20
        }
    }
    private var shadowY: CGFloat {
        switch elevation {
        case .flat: return 0; case .subtle: return 2
        case .raised: return 4; case .hero: return 6
        }
    }
}

extension View {
    func cardStyle(_ elevation: CardStyle.Elevation = .subtle) -> some View {
        modifier(CardStyle(elevation: elevation))
    }
}

// MARK: - COIL Nav Bar Modifier
// Apply to the root content view inside each NavigationStack.

struct CoilNavBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(AppColors.navBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    CoilWordmark()
                }
            }
    }
}

extension View {
    func coilNavBar() -> some View { modifier(CoilNavBarModifier()) }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.custom("Industry-Bold", size: 15))
            .textCase(.uppercase)
            .kerning(1.2)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, AppSpacing.xl)
            .background(isDisabled ? AnyShapeStyle(AppColors.mutedText) : AnyShapeStyle(AppColors.ctaBackground))
            .clipShape(Capsule())
            .shadow(color: AppColors.ctaBackground.opacity(0.30), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(AppAnimations.press, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.custom("Industry-Bold", size: 14))
            .textCase(.uppercase)
            .kerning(1.0)
            .foregroundColor(AppColors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(.clear)
            .overlay(Capsule().stroke(AppColors.accent, lineWidth: 1.5))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(AppAnimations.press, value: configuration.isPressed)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFonts.bodyMedium)
            .foregroundColor(AppColors.danger)
            .padding(.vertical, AppSpacing.md)
            .padding(.horizontal, AppSpacing.xl)
            .background(AppColors.danger.opacity(0.1))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(AppAnimations.press, value: configuration.isPressed)
    }
}

// MARK: - COIL Shared Components

/// Teal gradient rule with uppercase Industry-Bold title — use for all content section breaks.
struct CoilDividerHeader: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            Text(title)
                .font(AppFonts.sectionTitle)
                .textCase(.uppercase)
                .kerning(1.0)
                .foregroundColor(AppColors.primaryText)

            LinearGradient(
                colors: [AppColors.accent, AppColors.accent.opacity(0)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 2)
        }
    }
}

/// Small teal pill badge — "ACTIVE", "ON FIRE", count indicators, etc.
struct CoilBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppFonts.badge)
            .textCase(.uppercase)
            .kerning(1.0)
            .foregroundColor(AppColors.ctaText)
            .padding(.horizontal, AppSpacing.comfortable)
            .padding(.vertical, AppSpacing.nano + 1)
            .background(AppColors.accentDark)
            .clipShape(Capsule())
    }
}

// MARK: - Shared Components

struct CardSection<Content: View>: View {
    let icon: String
    let color: Color
    let title: String
    var required: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(AppFonts.bodySemiBold)
                    .foregroundColor(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12))
                    .cornerRadius(AppCorners.small - 1)
                Text(title)
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.secondaryText)
                if required {
                    Text("Required")
                        .font(AppFonts.captionMedium)
                        .foregroundColor(AppColors.danger.opacity(0.8))
                }
            }
            content
        }
        .cardStyle()
    }
}

struct StyledTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .font(AppFonts.body)
            .foregroundColor(AppColors.primaryText)
            .padding(AppSpacing.md)
            .background(AppColors.inputBackground)
            .cornerRadius(AppCorners.medium)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(AppColors.accent)

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.primaryText)
                Text(subtitle)
                    .font(AppFonts.small)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
            }

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, AppSpacing.xxl)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxl)
        .cardStyle()
    }
}

/// Standard error state (icon + title + message + Retry) used across screens
/// instead of ad-hoc error UI. The icon is intentionally generic so a
/// non-connectivity failure (e.g. a Firestore permission error) isn't mislabeled
/// as a wifi problem (audit #63).
struct ErrorStateView: View {
    var title: String = "Something went wrong"
    let message: String
    var systemImage: String = "exclamationmark.triangle"
    var retryTitle: String = "Try Again"
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundColor(AppColors.warning)

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.primaryText)
                Text(message)
                    .font(AppFonts.small)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
            }

            Button(action: onRetry) {
                Text(retryTitle)
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.horizontal, AppSpacing.xxl)
            .accessibilityIdentifier("errorState.retryButton")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxl)
        .cardStyle()
    }
}

struct LoadingStateView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
                .tint(AppColors.accent)
                .scaleEffect(1.2)
            Text(message)
                .font(AppFonts.small)
                .foregroundColor(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct QuickActionCard<Destination: View>: View {
    let icon: String
    let gradientColors: [Color]
    let title: String
    let subtitle: String
    let destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(AppFonts.bodyMedium)
                    .foregroundColor(gradientColors.first ?? AppColors.accent)
                    .frame(width: 40, height: 40)
                    .background((gradientColors.first ?? AppColors.accent).opacity(0.12))
                    .cornerRadius(AppCorners.small)

                VStack(alignment: .leading, spacing: AppSpacing.nano) {
                    Text(title)
                        .font(AppFonts.bodySemiBold)
                        .foregroundColor(AppColors.primaryText)
                    Text(subtitle)
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppFonts.smallSemiBold)
                    .foregroundColor(AppColors.mutedText)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md + 2)
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.card)
            .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(AppColors.cardBorder, lineWidth: 1))
            .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let gradientColors: [Color]
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(AppFonts.bodyMedium)
                    .foregroundColor(gradientColors.first ?? AppColors.accent)
                    .frame(width: 40, height: 40)
                    .background((gradientColors.first ?? AppColors.accent).opacity(0.12))
                    .cornerRadius(AppCorners.small)

                VStack(alignment: .leading, spacing: AppSpacing.nano) {
                    Text(title)
                        .font(AppFonts.bodySemiBold)
                        .foregroundColor(AppColors.primaryText)
                    Text(subtitle)
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppFonts.smallSemiBold)
                    .foregroundColor(AppColors.mutedText)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md + 2)
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.card)
            .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(AppColors.cardBorder, lineWidth: 1))
            .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
        }
    }
}

struct SectionHeader: View {
    let icon: String
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(AppFonts.bodySemiBold)
            Text(title)
                .font(AppFonts.cardTitle)
                .foregroundColor(AppColors.secondaryText)
            Spacer()
        }
    }
}

// MARK: - Chip Button

struct ChipButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(AppFonts.smallSemiBold)
                .foregroundColor(isSelected ? AppColors.ctaText : AppColors.primaryText)
                .padding(.horizontal, AppSpacing.md + 2)
                .padding(.vertical, AppSpacing.tight + 1)
                .background(isSelected ? AppColors.chipSelectedBg : Color.clear)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        // Was Color.black@15% — invisible against the dark card in
                        // dark mode, leaving unselected chips with no tappable
                        // boundary at all (the fill is clear). subtleBorder is the
                        // adaptive hairline meant for exactly this.
                        .stroke(isSelected ? AppColors.chipSelectedBorder : AppColors.subtleBorder, lineWidth: 1.5)
                )
        }
        // Selection was conveyed by color alone — announce it to VoiceOver and
        // colorblind users everywhere ChipButton is used (audit #68).
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangeSubviews(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity
        let subviewSizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var rows: [[Int]] = []
        var rowContentWidths: [CGFloat] = []
        var currentRow: [Int] = []
        var currentRowWidth: CGFloat = 0

        for (index, size) in subviewSizes.enumerated() {
            let itemWidth = size.width
            let spaceNeeded = currentRow.isEmpty ? itemWidth : currentRowWidth + spacing + itemWidth
            if spaceNeeded > maxWidth && !currentRow.isEmpty {
                rows.append(currentRow)
                rowContentWidths.append(currentRowWidth)
                currentRow = []; currentRowWidth = 0
            }
            currentRow.append(index)
            currentRowWidth = currentRow.count == 1 ? itemWidth : currentRowWidth + spacing + itemWidth
        }
        if !currentRow.isEmpty { rows.append(currentRow); rowContentWidths.append(currentRowWidth) }

        var positions = Array(repeating: CGPoint.zero, count: subviews.count)
        var currentY: CGFloat = 0
        for (rowIndex, row) in rows.enumerated() {
            let rowWidth = rowContentWidths[rowIndex]
            let startX: CGFloat = alignment == .center ? max(0, (maxWidth - rowWidth) / 2) : 0
            let rowHeight = row.map { subviewSizes[$0].height }.max() ?? 0
            var x = startX
            for itemIndex in row {
                positions[itemIndex] = CGPoint(x: x, y: currentY)
                x += subviewSizes[itemIndex].width + spacing
            }
            currentY += rowHeight + spacing
        }
        let totalHeight = max(0, currentY - spacing)
        return ArrangementResult(size: CGSize(width: maxWidth, height: totalHeight), positions: positions, sizes: subviewSizes)
    }

    private struct ArrangementResult {
        let size: CGSize; let positions: [CGPoint]; let sizes: [CGSize]
    }
}

// MARK: - Session Logging

struct SessionLoggingModifier: ViewModifier {
    let screenName: String
    func body(content: Content) -> some View {
        content
            .onAppear {
                SessionLogger.shared.logNavigation(.screenAppeared, screen: screenName)
                AnalyticsService.shared.logScreenView(screenName)
            }
            .onDisappear {
                SessionLogger.shared.logNavigation(.screenDisappeared, screen: screenName)
            }
    }
}

extension View {
    func trackScreen(_ name: String) -> some View { modifier(SessionLoggingModifier(screenName: name)) }
}

// MARK: - Shimmer

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(colors: [.clear, .white.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geometry.size.width * 0.6)
                        .offset(x: -geometry.size.width * 0.3 + phase * geometry.size.width * 1.6)
                        .allowsHitTesting(false)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}

// MARK: - Onboarding Dark Surface

enum OnboardingColors {
    static let cardBg     = Color.white.opacity(0.06)
    static let cardBorder = Color.white.opacity(0.10)
    static let inputBg    = Color.white.opacity(0.08)
    static let chipIdle   = Color.white.opacity(0.10)
    static let chipBorder = Color.white.opacity(0.14)
    static let subLabel   = Color.white.opacity(0.45)
    static let muted      = Color.white.opacity(0.35)
}

struct DarkTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboardType)
            .font(AppFonts.body)
            .foregroundColor(.white)
            .padding(AppSpacing.md)
            .background(OnboardingColors.inputBg)
            .cornerRadius(AppCorners.medium)
            .overlay(
                RoundedRectangle(cornerRadius: AppCorners.medium)
                    .stroke(OnboardingColors.cardBorder, lineWidth: 1)
            )
    }
}

struct OnboardingFieldLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(AppFonts.fieldLabel)
            .textCase(.uppercase)
            .kerning(1.2)
            .foregroundColor(OnboardingColors.subLabel)
    }
}

struct DarkChipButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    var accentColor: Color = AppColors.accent
    var compact: Bool = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(compact ? AppFonts.smallMedium : AppFonts.bodyMedium)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? AppSpacing.xs + 2 : AppSpacing.md)
                .padding(.horizontal, compact ? AppSpacing.sm : 0)
                .background(isSelected ? accentColor : OnboardingColors.chipIdle)
                .cornerRadius(compact ? AppCorners.small : AppCorners.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? AppCorners.small : AppCorners.medium)
                        .stroke(isSelected ? Color.clear : OnboardingColors.chipBorder, lineWidth: 1)
                )
        }
    }
}

// MARK: - Celebration Overlay

struct CelebrationOverlay: View {
    let icon: String
    let message: String
    var iconColor: Color = AppColors.success

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(iconColor)
            Text(message)
                .font(AppFonts.cardTitle)
                .foregroundColor(AppColors.primaryText)
        }
        .padding(AppSpacing.xxl)
        .background(.ultraThinMaterial)
        .cornerRadius(AppCorners.xl)
        .transition(.scale.combined(with: .opacity))
    }
}
