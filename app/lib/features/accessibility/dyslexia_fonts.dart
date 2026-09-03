import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Dyslexia-friendly fonts provider
final dyslexiaFontProvider = StateNotifierProvider<DyslexiaFontNotifier, DyslexiaFontSettings>((ref) {
  return DyslexiaFontNotifier();
});

enum DyslexiaFont {
  openDyslexic,
  comicSans,
  verdana,
  arial,
  trebuchet,
  centuryGothic,
  lexend,
  atkinson,
  systemDefault,
}

class DyslexiaFontSettings {
  final DyslexiaFont font;
  final double fontSize;
  final double letterSpacing;
  final double wordSpacing;
  final double lineHeight;
  final bool enabled;
  final bool boldText;
  final bool underlineLinks;
  final TextAlign textAlign;
  final Color? textColor;
  final Color? backgroundColor;
  final bool reduceAnimations;
  
  DyslexiaFontSettings({
    this.font = DyslexiaFont.systemDefault,
    this.fontSize = 16.0,
    this.letterSpacing = 0.15,
    this.wordSpacing = 1.2,
    this.lineHeight = 1.8,
    this.enabled = false,
    this.boldText = false,
    this.underlineLinks = true,
    this.textAlign = TextAlign.left,
    this.textColor,
    this.backgroundColor,
    this.reduceAnimations = true,
  });
  
  DyslexiaFontSettings copyWith({
    DyslexiaFont? font,
    double? fontSize,
    double? letterSpacing,
    double? wordSpacing,
    double? lineHeight,
    bool? enabled,
    bool? boldText,
    bool? underlineLinks,
    TextAlign? textAlign,
    Color? textColor,
    Color? backgroundColor,
    bool? reduceAnimations,
  }) {
    return DyslexiaFontSettings(
      font: font ?? this.font,
      fontSize: fontSize ?? this.fontSize,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      wordSpacing: wordSpacing ?? this.wordSpacing,
      lineHeight: lineHeight ?? this.lineHeight,
      enabled: enabled ?? this.enabled,
      boldText: boldText ?? this.boldText,
      underlineLinks: underlineLinks ?? this.underlineLinks,
      textAlign: textAlign ?? this.textAlign,
      textColor: textColor ?? this.textColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      reduceAnimations: reduceAnimations ?? this.reduceAnimations,
    );
  }
  
  String get fontFamily {
    switch (font) {
      case DyslexiaFont.openDyslexic:
        return 'OpenDyslexic';
      case DyslexiaFont.comicSans:
        return 'Comic Sans MS';
      case DyslexiaFont.verdana:
        return 'Verdana';
      case DyslexiaFont.arial:
        return 'Arial';
      case DyslexiaFont.trebuchet:
        return 'Trebuchet MS';
      case DyslexiaFont.centuryGothic:
        return 'Century Gothic';
      case DyslexiaFont.lexend:
        return 'Lexend';
      case DyslexiaFont.atkinson:
        return 'Atkinson Hyperlegible';
      case DyslexiaFont.systemDefault:
        return '';
    }
  }
  
  TextStyle getTextStyle({
    double? customFontSize,
    FontWeight? fontWeight,
    Color? color,
  }) {
    if (!enabled) {
      return TextStyle(
        fontSize: customFontSize,
        fontWeight: fontWeight,
        color: color,
      );
    }
    
    return TextStyle(
      fontFamily: fontFamily.isNotEmpty ? fontFamily : null,
      fontSize: customFontSize ?? fontSize,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      height: lineHeight,
      fontWeight: boldText ? FontWeight.bold : fontWeight,
      color: color ?? textColor,
    );
  }
}

class DyslexiaFontNotifier extends StateNotifier<DyslexiaFontSettings> {
  static const String _storageKey = 'dyslexia_font_settings';
  
  DyslexiaFontNotifier() : super(DyslexiaFontSettings()) {
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    state = DyslexiaFontSettings(
      font: DyslexiaFont.values[prefs.getInt('${_storageKey}_font') ?? 0],
      fontSize: prefs.getDouble('${_storageKey}_fontSize') ?? 16.0,
      letterSpacing: prefs.getDouble('${_storageKey}_letterSpacing') ?? 0.15,
      wordSpacing: prefs.getDouble('${_storageKey}_wordSpacing') ?? 1.2,
      lineHeight: prefs.getDouble('${_storageKey}_lineHeight') ?? 1.8,
      enabled: prefs.getBool('${_storageKey}_enabled') ?? false,
      boldText: prefs.getBool('${_storageKey}_boldText') ?? false,
      underlineLinks: prefs.getBool('${_storageKey}_underlineLinks') ?? true,
      textAlign: TextAlign.values[prefs.getInt('${_storageKey}_textAlign') ?? 0],
      reduceAnimations: prefs.getBool('${_storageKey}_reduceAnimations') ?? true,
    );
  }
  
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setInt('${_storageKey}_font', state.font.index);
    await prefs.setDouble('${_storageKey}_fontSize', state.fontSize);
    await prefs.setDouble('${_storageKey}_letterSpacing', state.letterSpacing);
    await prefs.setDouble('${_storageKey}_wordSpacing', state.wordSpacing);
    await prefs.setDouble('${_storageKey}_lineHeight', state.lineHeight);
    await prefs.setBool('${_storageKey}_enabled', state.enabled);
    await prefs.setBool('${_storageKey}_boldText', state.boldText);
    await prefs.setBool('${_storageKey}_underlineLinks', state.underlineLinks);
    await prefs.setInt('${_storageKey}_textAlign', state.textAlign.index);
    await prefs.setBool('${_storageKey}_reduceAnimations', state.reduceAnimations);
  }
  
  void toggleEnabled() {
    state = state.copyWith(enabled: !state.enabled);
    _saveSettings();
  }
  
  void setFont(DyslexiaFont font) {
    state = state.copyWith(font: font);
    _saveSettings();
  }
  
  void setFontSize(double size) {
    state = state.copyWith(fontSize: size.clamp(12.0, 32.0));
    _saveSettings();
  }
  
  void setLetterSpacing(double spacing) {
    state = state.copyWith(letterSpacing: spacing.clamp(0.0, 1.0));
    _saveSettings();
  }
  
  void setWordSpacing(double spacing) {
    state = state.copyWith(wordSpacing: spacing.clamp(1.0, 3.0));
    _saveSettings();
  }
  
  void setLineHeight(double height) {
    state = state.copyWith(lineHeight: height.clamp(1.0, 3.0));
    _saveSettings();
  }
  
  void toggleBoldText() {
    state = state.copyWith(boldText: !state.boldText);
    _saveSettings();
  }
  
  void toggleUnderlineLinks() {
    state = state.copyWith(underlineLinks: !state.underlineLinks);
    _saveSettings();
  }
  
  void setTextAlign(TextAlign align) {
    state = state.copyWith(textAlign: align);
    _saveSettings();
  }
  
  void setTextColor(Color color) {
    state = state.copyWith(textColor: color);
    _saveSettings();
  }
  
  void setBackgroundColor(Color color) {
    state = state.copyWith(backgroundColor: color);
    _saveSettings();
  }
  
  void toggleReduceAnimations() {
    state = state.copyWith(reduceAnimations: !state.reduceAnimations);
    _saveSettings();
  }
  
  void applyPreset(DyslexiaPreset preset) {
    switch (preset) {
      case DyslexiaPreset.mild:
        state = DyslexiaFontSettings(
          font: DyslexiaFont.verdana,
          fontSize: 16.0,
          letterSpacing: 0.1,
          wordSpacing: 1.2,
          lineHeight: 1.6,
          enabled: true,
          boldText: false,
          underlineLinks: true,
          reduceAnimations: false,
        );
        break;
      case DyslexiaPreset.moderate:
        state = DyslexiaFontSettings(
          font: DyslexiaFont.openDyslexic,
          fontSize: 18.0,
          letterSpacing: 0.15,
          wordSpacing: 1.5,
          lineHeight: 1.8,
          enabled: true,
          boldText: false,
          underlineLinks: true,
          reduceAnimations: true,
        );
        break;
      case DyslexiaPreset.severe:
        state = DyslexiaFontSettings(
          font: DyslexiaFont.openDyslexic,
          fontSize: 20.0,
          letterSpacing: 0.2,
          wordSpacing: 2.0,
          lineHeight: 2.0,
          enabled: true,
          boldText: true,
          underlineLinks: true,
          reduceAnimations: true,
        );
        break;
    }
    _saveSettings();
  }
}

enum DyslexiaPreset {
  mild,
  moderate,
  severe,
}

// Dyslexia-friendly text widget
class DyslexiaText extends ConsumerWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool selectable;
  
  const DyslexiaText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.selectable = false,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(dyslexiaFontProvider);
    
    final effectiveStyle = settings.getTextStyle(
      customFontSize: style?.fontSize,
      fontWeight: style?.fontWeight,
      color: style?.color,
    ).merge(style);
    
    final effectiveAlign = settings.enabled 
      ? (textAlign ?? settings.textAlign)
      : textAlign;
    
    if (selectable) {
      return SelectableText(
        text,
        style: effectiveStyle,
        textAlign: effectiveAlign,
        maxLines: maxLines,
      );
    }
    
    return Text(
      text,
      style: effectiveStyle,
      textAlign: effectiveAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

// Dyslexia-friendly rich text widget
class DyslexiaRichText extends ConsumerWidget {
  final TextSpan textSpan;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  
  const DyslexiaRichText({
    super.key,
    required this.textSpan,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(dyslexiaFontProvider);
    
    final effectiveAlign = settings.enabled 
      ? (textAlign ?? settings.textAlign)
      : textAlign;
    
    TextSpan applySettings(TextSpan span) {
      final style = settings.getTextStyle(
        customFontSize: span.style?.fontSize,
        fontWeight: span.style?.fontWeight,
        color: span.style?.color,
      ).merge(span.style);
      
      return TextSpan(
        text: span.text,
        style: style,
        children: span.children?.map((child) {
          if (child is TextSpan) {
            return applySettings(child);
          }
          return child;
        }).toList(),
        recognizer: span.recognizer,
      );
    }
    
    return RichText(
      text: settings.enabled ? applySettings(textSpan) : textSpan,
      textAlign: effectiveAlign ?? TextAlign.left,
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}

// Color overlays for dyslexia
class DyslexiaColorOverlays {
  static const Map<String, Color> overlays = {
    'None': Colors.transparent,
    'Yellow': Color(0x20FFFF00),
    'Blue': Color(0x200000FF),
    'Green': Color(0x2000FF00),
    'Pink': Color(0x20FF1493),
    'Purple': Color(0x209370DB),
    'Orange': Color(0x20FFA500),
    'Peach': Color(0x20FFDAB9),
  };
  
  static Widget applyOverlay({
    required Widget child,
    required String overlayName,
    double opacity = 0.1,
  }) {
    final color = overlays[overlayName];
    
    if (color == null || color == Colors.transparent) {
      return child;
    }
    
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              color: color.withOpacity(opacity),
            ),
          ),
        ),
      ],
    );
  }
}

// Reading ruler widget
class ReadingRuler extends StatefulWidget {
  final Widget child;
  final double rulerHeight;
  final Color rulerColor;
  final bool enabled;
  
  const ReadingRuler({
    super.key,
    required this.child,
    this.rulerHeight = 40.0,
    this.rulerColor = Colors.yellow,
    this.enabled = true,
  });
  
  @override
  State<ReadingRuler> createState() => _ReadingRulerState();
}

class _ReadingRulerState extends State<ReadingRuler> {
  double _rulerPosition = 0;
  
  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _rulerPosition = details.localPosition.dy - (widget.rulerHeight / 2);
        });
      },
      child: Stack(
        children: [
          widget.child,
          Positioned(
            top: _rulerPosition,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: widget.rulerHeight,
                decoration: BoxDecoration(
                  color: widget.rulerColor.withOpacity(0.2),
                  border: Border(
                    top: BorderSide(
                      color: widget.rulerColor.withOpacity(0.5),
                      width: 2,
                    ),
                    bottom: BorderSide(
                      color: widget.rulerColor.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}