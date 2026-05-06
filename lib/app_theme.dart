import 'package:flutter/material.dart';

class AppTheme {
  // ── Paleta naranja/ámbar oscura ──────────────────────────────────────────
  static const _amber        = Color(0xFFFF8C00);   // naranja principal
  static const _amberLight   = Color(0xFFFFAD3B);   // naranja claro
  static const _amberDark    = Color(0xFFCC6F00);   // naranja oscuro

  // Fondos dark
  static const _darkBg       = Color(0xFF111318);   // fondo principal
  static const _darkCard     = Color(0xFF1C1F28);   // superficie de cards
  static const _darkCardAlt  = Color(0xFF242836);   // superficie alt
  static const _darkBorder   = Color(0xFF2E3340);   // bordes

  // Fondos light
  static const _lightBg      = Color(0xFFF4F5FA);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightAlt     = Color(0xFFEEF0F8);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      brightness: Brightness.light,
      seedColor: _amber,
      primary: _amber,
      secondary: _amberLight,
      tertiary: _amberDark,
      surface: _lightSurface,
    ).copyWith(
      surfaceContainerHighest: _lightAlt,
      surfaceContainer: const Color(0xFFEAF0FA),
      onSurface: const Color(0xFF1A1D26),
    );
    return _baseTheme(scheme).copyWith(
      scaffoldBackgroundColor: _lightBg,
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      brightness: Brightness.dark,
      seedColor: _amber,
      primary: _amber,
      secondary: _amberLight,
      tertiary: _amberDark,
      surface: _darkCard,
    ).copyWith(
      surfaceContainerHighest: _darkCardAlt,
      surfaceContainer: _darkBorder,
      onSurface: const Color(0xFFE8EAF2),
      outline: _darkBorder,
    );
    return _baseTheme(scheme).copyWith(
      scaffoldBackgroundColor: _darkBg,
    );
  }

  static ThemeData _baseTheme(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.35)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.75),
        labelStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.8)),
        hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.6)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selectedColor: scheme.primary.withValues(alpha: 0.18),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.25)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textTheme: Typography.blackMountainView.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
    );
  }
}

// ── Constantes de color accesibles ──────────────────────────────────────────
class AppColors {
  static const amber     = Color(0xFFFF8C00);
  static const amberGlow = Color(0xFFFFAD3B);
  static const darkBg    = Color(0xFF111318);
  static const darkCard  = Color(0xFF1C1F28);
  static const green     = Color(0xFF4CAF82);
  static const red       = Color(0xFFE05C5C);
  static const blue      = Color(0xFF4B9EFF);
  static const purple    = Color(0xFF9B7FFF);
}

// ── Theme controller ─────────────────────────────────────────────────────────
class ThemeModeController extends ValueNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.dark); // dark por defecto

  void toggleMode(Brightness brightness) {
    if (value == ThemeMode.system) {
      value = brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
      return;
    }
    value = value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }
}

class ThemeModeScope extends InheritedNotifier<ThemeModeController> {
  const ThemeModeScope({
    super.key,
    required ThemeModeController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemeModeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeModeScope>();
    assert(scope != null, 'ThemeModeScope no encontrado en el arbol');
    return scope!.notifier!;
  }
}

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = ThemeModeScope.of(context);
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    return IconButton(
      tooltip: isDark ? 'Modo claro' : 'Modo oscuro',
      onPressed: () => ctrl.toggleMode(brightness),
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
    );
  }
}

// ── Fondo con gradiente sutil ─────────────────────────────────────────────────
class GradientBody extends StatelessWidget {
  final Widget child;
  const GradientBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF111318),
                  Color(0xFF161922),
                  Color(0xFF111318),
                ],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFF4F5FA),
                  const Color(0xFFEEF0F8),
                  const Color(0xFFF4F5FA),
                ],
              ),
      ),
      child: child,
    );
  }
}

// ── Card base ─────────────────────────────────────────────────────────────────
class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;

  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cardColor = color ?? scheme.surface;
    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.3),
            ),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
