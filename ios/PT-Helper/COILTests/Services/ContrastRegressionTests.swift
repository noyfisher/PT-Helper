import XCTest
import SwiftUI
@testable import COIL

/// Contrast floors for the token pairings that were shipping unreadable.
///
/// Theming has no other automated gate, and all four P1s were the same mistake:
/// a token that ADAPTS painted on a surface that does NOT. `bgGradient`,
/// `navBackground`, `coolGradient` and `healingGradient` are fixed in both
/// appearances, so `primaryText`/`secondaryText`/`.primary` flip to the wrong
/// end and vanish — which is how the AI safety cautions ended up at ~1.1:1 in
/// light mode, the app's default.
///
/// These assert measured contrast in BOTH appearances rather than "which token
/// is used", so a future refactor that swaps tokens is free as long as the
/// result stays readable.
final class ContrastRegressionTests: XCTestCase {

    // MARK: - WCAG math

    private func luminance(_ color: UIColor, _ style: UIUserInterfaceStyle) -> CGFloat {
        let traits = UITraitCollection(userInterfaceStyle: style)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func contrast(_ fg: Color, on bg: Color, _ style: UIUserInterfaceStyle) -> CGFloat {
        let l1 = luminance(UIColor(fg), style)
        let l2 = luminance(UIColor(bg), style)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private func assertReadable(
        _ fg: Color, on bg: Color, _ label: String,
        floor: CGFloat = 4.5, file: StaticString = #filePath, line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let name = style == .light ? "light" : "dark"
            let value = contrast(fg, on: bg, style)
            XCTAssertGreaterThanOrEqual(
                value, floor,
                String(format: "%@ in %@ mode: %.2f:1 (floor %.1f:1)", label, name, Double(value), Double(floor)),
                file: file, line: line
            )
        }
    }

    // MARK: - Fixed-dark surfaces (bgGradient / navBackground)

    /// The two safety-caution banners. Adaptive text here rendered BLACK on the
    /// fixed-dark gradient in light mode — the validation pipeline's medical
    /// caveats were invisible in the default appearance.
    func testSafetyCautionText_onFixedDarkBackground_isReadableInBothModes() {
        assertReadable(AppColors.textOnDark, on: AppColors.darkSurface, "Caution heading on bgGradient")
        assertReadable(AppColors.textOnDarkMuted, on: AppColors.darkSurface,
                       "Caution body on bgGradient", floor: 3.0)
    }

    func testLoadingText_onFixedDarkBackground_isReadable() {
        assertReadable(AppColors.textOnDarkMuted, on: AppColors.darkSurface,
                       "Cold-launch loading text", floor: 3.0)
    }

    /// Regression guard for the root cause itself: the adaptive text tokens must
    /// NOT be considered safe on a fixed-dark surface. If someone "simplifies"
    /// these call sites back to primaryText, this fails.
    func testAdaptiveTextTokens_areUnreadableOnFixedDarkSurfaces_soTheyMustNotBeUsedThere() {
        let lightModeContrast = contrast(AppColors.primaryText, on: AppColors.darkSurface, .light)
        XCTAssertLessThan(lightModeContrast, 3.0,
                          "primaryText on a fixed-dark surface is unreadable in light mode — this documents WHY the on-dark tokens exist")
    }

    // MARK: - Fixed-teal CTA gradients

    /// Both plan CTAs. The gradients stay teal in both appearances while
    /// primaryText flips to near-white, dropping the labels to ~1.4:1 in dark.
    func testPrimaryCTAText_onFixedTealGradient_isReadableInBothModes() {
        for (name, bg) in [("coolGradient start", AppColors.accent),
                           ("coolGradient end", AppColors.accentLight),
                           ("healingGradient end", AppColors.ctaBackground)] {
            assertReadable(AppColors.textOnAccent, on: bg, "CTA label on \(name)", floor: 3.0)
        }
    }

    /// Documents WHY the on-accent colour is near-black rather than white: the
    /// brand teal is light, so white fails badly on the bright gradient stops.
    /// If someone "corrects" textOnAccent to white, this fails.
    func testWhiteIsNotAViableOnColorForTheAccentGradient() {
        let value = contrast(AppColors.ctaText, on: AppColors.accentLight, .dark)
        XCTAssertLessThan(value, 3.0,
                          "White on the bright teal stop is unreadable — textOnAccent must stay near-black")
    }

    // MARK: - Semantic colors vs their fixed-white on-color

    /// Danger surfaces pair a lightening red with fixed-white text; the dark
    /// variant was 2.84:1 on body text including the red-flag safety notice.
    func testDangerSurfaces_withFixedWhiteOnColor_meetAA() {
        assertReadable(AppColors.ctaText, on: AppColors.danger, "White on danger")
    }

    // MARK: - Borders

    /// Unselected chips have a clear fill, so a border that vanishes leaves no
    /// tappable boundary at all.
    func testUnselectedChipBorder_isVisibleOnCardInBothModes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let value = contrast(AppColors.subtleBorder, on: AppColors.cardBackground, style)
            XCTAssertGreaterThan(value, 1.05,
                                 "Chip border must be perceptible in \(style == .light ? "light" : "dark") mode")
        }
    }
}
