import 'package:flutter/material.dart';
import 'glass_tokens.dart';

/// Leaf values of the default Glass dark identity. The Glass preset, the
/// legacy GlassColors palette and GlassThemeData's const defaults all read
/// from these so the token system stays the single source.
class GlassCoreColors {
  static const Color primary = Color(0xFF667EEA);
  static const Color secondary = Color(0xFF764BA2);
  static const Color accent = Color(0xFF4FACFE);
  static const Color bgBase = Color(0xFF0A0E21);
  static const Color glassFill = Color(0x1AFFFFFF);
  static const Color glassStroke = Color(0x2DFFFFFF);
  static const List<Color> backgroundGradient = [
    Color(0xFF0A0E21),
    Color(0xFF1A1F3C),
    Color(0xFF0F2027),
  ];
  static const List<Color> primaryGradient = [Color(0xFF667EEA), Color(0xFF764BA2)];
  static const List<Color> accentGradient = [Color(0xFF4FACFE), Color(0xFF00F2FE)];
  static const List<Color> auroraColors = [
    Color(0xFF00D2FF),
    Color(0xFF3A7BD5),
    Color(0xFF7F00FF),
    Color(0xFFE100FF),
  ];

  const GlassCoreColors._();
}

/// A named theme preset: a light/dark palette pair plus display metadata.
class GlassThemePreset {
  final String id;
  final String name;
  final GlassColorTokens light;
  final GlassColorTokens dark;

  const GlassThemePreset({
    required this.id,
    required this.name,
    required this.light,
    required this.dark,
  });

  GlassColorTokens resolve(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

class GlassPresets {
  /// Current indigo/violet glass identity.
  static const GlassThemePreset glass = GlassThemePreset(
    id: 'glass',
    name: 'Glass',
    dark: GlassColorTokens(
      primary: GlassCoreColors.primary,
      secondary: GlassCoreColors.secondary,
      accent: GlassCoreColors.accent,
      accentSoft: Color(0x334FACFE),
      textHigh: Color(0xFFFFFFFF),
      textMedium: Color(0xB3FFFFFF),
      textLow: Color(0x99FFFFFF),
      glassFill: GlassCoreColors.glassFill,
      glassStroke: GlassCoreColors.glassStroke,
      overlay: Color(0x66000000),
      success: Color(0xFF4ADE80),
      warning: Color(0xFFFBBF24),
      error: Color(0xFFF87171),
      bgBase: GlassCoreColors.bgBase,
      backgroundGradient: GlassCoreColors.backgroundGradient,
      primaryGradient: GlassCoreColors.primaryGradient,
      accentGradient: GlassCoreColors.accentGradient,
      auroraColors: GlassCoreColors.auroraColors,
      brightness: Brightness.dark,
    ),
    light: GlassColorTokens(
      primary: Color(0xFF5A6FD8),
      secondary: Color(0xFF8A5FB0),
      accent: Color(0xFF4F6BE8),
      accentSoft: Color(0x24667EEA),
      textHigh: Color(0xFF1A1F3C),
      textMedium: Color(0xFF4A5070),
      textLow: Color(0xFF7A7FA0),
      glassFill: Color(0x59FFFFFF),
      glassStroke: Color(0x80FFFFFF),
      overlay: Color(0x33000000),
      success: Color(0xFF16A34A),
      warning: Color(0xFFD97706),
      error: Color(0xFFDC2626),
      bgBase: Color(0xFFF0F2FA),
      backgroundGradient: [Color(0xFFEDF0FA), Color(0xFFE2E7F6), Color(0xFFF3F0FA)],
      primaryGradient: [Color(0xFF8296F0), Color(0xFF9C7CBE)],
      accentGradient: [Color(0xFF7FA8F5), Color(0xFF54C8F5)],
      auroraColors: [Color(0xFF7FA8F5), Color(0xFF54C8F5), Color(0xFFB08CE8), Color(0xFFE39BD6)],
      brightness: Brightness.light,
    ),
  );

  /// Airy bright glass: near-white surfaces, dark text.
  static const GlassThemePreset glassLight = GlassThemePreset(
    id: 'glass_light',
    name: 'Glass Light',
    dark: GlassColorTokens(
      primary: Color(0xFF7B8FF0),
      secondary: Color(0xFF8F6BBE),
      accent: Color(0xFF6FC2FF),
      accentSoft: Color(0x336FC2FF),
      textHigh: Color(0xFFFFFFFF),
      textMedium: Color(0xC0FFFFFF),
      textLow: Color(0xA0FFFFFF),
      glassFill: Color(0x24FFFFFF),
      glassStroke: Color(0x3DFFFFFF),
      overlay: Color(0x59000000),
      success: Color(0xFF5CE68F),
      warning: Color(0xFFfcc63A),
      error: Color(0xFFFB8A8A),
      bgBase: Color(0xFF1E2440),
      backgroundGradient: [Color(0xFF1E2440), Color(0xFF2B3357), Color(0xFF232A46)],
      primaryGradient: [Color(0xFF7B8FF0), Color(0xFF9C7CBE)],
      accentGradient: [Color(0xFF6FC2FF), Color(0xFF4FE0F5)],
      auroraColors: [Color(0xFF4FD8FF), Color(0xFF6E9BE0), Color(0xFF9A7CFF), Color(0xFFE86FE8)],
      brightness: Brightness.dark,
    ),
    light: GlassColorTokens(
      primary: Color(0xFF4F5FB8),
      secondary: Color(0xFF6E5494),
      accent: Color(0xFF3D55C9),
      accentSoft: Color(0x1F3D55C9),
      textHigh: Color(0xFF171B32),
      textMedium: Color(0xFF3F4562),
      textLow: Color(0xFF70759A),
      glassFill: Color(0x73FFFFFF),
      glassStroke: Color(0xB3FFFFFF),
      overlay: Color(0x2E000000),
      success: Color(0xFF15803D),
      warning: Color(0xFFB45309),
      error: Color(0xFFB91C1C),
      bgBase: Color(0xFFFAFBFE),
      backgroundGradient: [Color(0xFFFBFCFE), Color(0xFFF3F5FB), Color(0xFFFDFCFE)],
      primaryGradient: [Color(0xFF8296F0), Color(0xFF9C7CBE)],
      accentGradient: [Color(0xFF6F92E8), Color(0xFF54B0F0)],
      auroraColors: [Color(0xFF8FB5F8), Color(0xFF6FCBE8), Color(0xFFB39BE8), Color(0xFFE8B3D6)],
      brightness: Brightness.light,
    ),
  );

  /// Teal/cyan accent variant.
  static const GlassThemePreset aurora = GlassThemePreset(
    id: 'aurora',
    name: 'Aurora',
    dark: GlassColorTokens(
      primary: Color(0xFF14B8A6),
      secondary: Color(0xFF0EA5E9),
      accent: Color(0xFF22D3EE),
      accentSoft: Color(0x3322D3EE),
      textHigh: Color(0xFFFFFFFF),
      textMedium: Color(0xB3FFFFFF),
      textLow: Color(0x99FFFFFF),
      glassFill: Color(0x1AFFFFFF),
      glassStroke: Color(0x2DFFFFFF),
      overlay: Color(0x66000000),
      success: Color(0xFF4ADE80),
      warning: Color(0xFFFBBF24),
      error: Color(0xFFF87171),
      bgBase: Color(0xFF04161A),
      backgroundGradient: [Color(0xFF04161A), Color(0xFF0B2B33), Color(0xFF071A2B)],
      primaryGradient: [Color(0xFF14B8A6), Color(0xFF0EA5E9)],
      accentGradient: [Color(0xFF22D3EE), Color(0xFF2DD4BF)],
      auroraColors: [Color(0xFF2DD4BF), Color(0xFF22D3EE), Color(0xFF38BDF8), Color(0xFF7DD3FC)],
      brightness: Brightness.dark,
    ),
    light: GlassColorTokens(
      primary: Color(0xFF0D9488),
      secondary: Color(0xFF0284C7),
      accent: Color(0xFF0891B2),
      accentSoft: Color(0x1F0891B2),
      textHigh: Color(0xFF0F2E2B),
      textMedium: Color(0xFF3D5A56),
      textLow: Color(0xFF6E8A86),
      glassFill: Color(0x59FFFFFF),
      glassStroke: Color(0x80FFFFFF),
      overlay: Color(0x33000000),
      success: Color(0xFF16A34A),
      warning: Color(0xFFD97706),
      error: Color(0xFFDC2626),
      bgBase: Color(0xFFEFF8F7),
      backgroundGradient: [Color(0xFFEAF6F4), Color(0xFFDFF0F1), Color(0xFFEAF3FA)],
      primaryGradient: [Color(0xFF2DD4BF), Color(0xFF38BDF8)],
      accentGradient: [Color(0xFF22D3EE), Color(0xFF2DD4BF)],
      auroraColors: [Color(0xFF5EEAD4), Color(0xFF67E8F9), Color(0xFF7DD3FC), Color(0xFF99F6E4)],
      brightness: Brightness.light,
    ),
  );

  /// Warm amber/orange variant.
  static const GlassThemePreset ember = GlassThemePreset(
    id: 'ember',
    name: 'Ember',
    dark: GlassColorTokens(
      primary: Color(0xFFF59E0B),
      secondary: Color(0xFFEF6C00),
      accent: Color(0xFFFB923C),
      accentSoft: Color(0x33FB923C),
      textHigh: Color(0xFFFFFFFF),
      textMedium: Color(0xB3FFFFFF),
      textLow: Color(0x99FFFFFF),
      glassFill: Color(0x1AFFFFFF),
      glassStroke: Color(0x2DFFFFFF),
      overlay: Color(0x66000000),
      success: Color(0xFF4ADE80),
      warning: Color(0xFFFBBF24),
      error: Color(0xFFF87171),
      bgBase: Color(0xFF190D06),
      backgroundGradient: [Color(0xFF190D06), Color(0xFF2B1710), Color(0xFF1F0F0A)],
      primaryGradient: [Color(0xFFF59E0B), Color(0xFFEF6C00)],
      accentGradient: [Color(0xFFFB923C), Color(0xFFFBBF24)],
      auroraColors: [Color(0xFFFBBF24), Color(0xFFFB923C), Color(0xFFF97316), Color(0xFFFDE68A)],
      brightness: Brightness.dark,
    ),
    light: GlassColorTokens(
      primary: Color(0xFFB45309),
      secondary: Color(0xFFC2410C),
      accent: Color(0xFFD97706),
      accentSoft: Color(0x1FD97706),
      textHigh: Color(0xFF2D1B0E),
      textMedium: Color(0xFF5C4630),
      textLow: Color(0xFF8C7458),
      glassFill: Color(0x59FFFFFF),
      glassStroke: Color(0x80FFFFFF),
      overlay: Color(0x33000000),
      success: Color(0xFF16A34A),
      warning: Color(0xFFB45309),
      error: Color(0xFFDC2626),
      bgBase: Color(0xFFFDF6EE),
      backgroundGradient: [Color(0xFFFBF3E8), Color(0xFFF7E9D7), Color(0xFFFDF4EC)],
      primaryGradient: [Color(0xFFFBBF24), Color(0xFFF97316)],
      accentGradient: [Color(0xFFFCD34D), Color(0xFFFB923C)],
      auroraColors: [Color(0xFFFDE68A), Color(0xFFFCD34D), Color(0xFFFDBA74), Color(0xFFFED7AA)],
      brightness: Brightness.light,
    ),
  );

  /// Desaturated slate, no chromatic gradient.
  static const GlassThemePreset mono = GlassThemePreset(
    id: 'mono',
    name: 'Mono',
    dark: GlassColorTokens(
      primary: Color(0xFF94A3B8),
      secondary: Color(0xFF64748B),
      accent: Color(0xFFCBD5E1),
      accentSoft: Color(0x33CBD5E1),
      textHigh: Color(0xFFFFFFFF),
      textMedium: Color(0xB3FFFFFF),
      textLow: Color(0x99FFFFFF),
      glassFill: Color(0x1AFFFFFF),
      glassStroke: Color(0x2DFFFFFF),
      overlay: Color(0x66000000),
      success: Color(0xFF86EFAC),
      warning: Color(0xFFE5C07B),
      error: Color(0xFFFCA5A5),
      bgBase: Color(0xFF0D1117),
      backgroundGradient: [Color(0xFF0D1117), Color(0xFF161B22), Color(0xFF11151C)],
      primaryGradient: [Color(0xFF334155), Color(0xFF1E293B)],
      accentGradient: [Color(0xFF94A3B8), Color(0xFFCBD5E1)],
      auroraColors: [Color(0xFFCBD5E1), Color(0xFF94A3B8), Color(0xFF64748B), Color(0xFFE2E8F0)],
      brightness: Brightness.dark,
    ),
    light: GlassColorTokens(
      primary: Color(0xFF475569),
      secondary: Color(0xFF334155),
      accent: Color(0xFF334155),
      accentSoft: Color(0x1F334155),
      textHigh: Color(0xFF1E293B),
      textMedium: Color(0xFF475569),
      textLow: Color(0xFF7C8A9E),
      glassFill: Color(0x59FFFFFF),
      glassStroke: Color(0x80FFFFFF),
      overlay: Color(0x33000000),
      success: Color(0xFF15803D),
      warning: Color(0xFFA16207),
      error: Color(0xFFB91C1C),
      bgBase: Color(0xFFF5F6F8),
      backgroundGradient: [Color(0xFFF2F4F7), Color(0xFFEAEDF2), Color(0xFFF7F8FA)],
      primaryGradient: [Color(0xFF64748B), Color(0xFF475569)],
      accentGradient: [Color(0xFF94A3B8), Color(0xFF64748B)],
      auroraColors: [Color(0xFFCBD5E1), Color(0xFF94A3B8), Color(0xFFE2E8F0), Color(0xFF64748B)],
      brightness: Brightness.light,
    ),
  );

  static const List<GlassThemePreset> all = [
    glass,
    glassLight,
    aurora,
    ember,
    mono,
  ];

  static const GlassThemePreset defaultPreset = glass;

  static const String defaultPresetId = 'glass';

  static GlassThemePreset byId(String? id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return defaultPreset;
  }

  const GlassPresets._();
}
