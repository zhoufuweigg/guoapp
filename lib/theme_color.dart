enum ThemeColor {
  orange('暖橙', 0xFFFF664F),
  rose('玫红', 0xFFC25485),
  amber('琥珀', 0xFFB37000),
  teal('青绿', 0xFF009C84),
  blue('海蓝', 0xFF0089D0),
  violet('蓝紫', 0xFF7970D5);

  const ThemeColor(this.label, this.seed);
  final String label;
  final int seed;

  static ThemeColor? byName(Object? name) =>
      values.where((color) => color.name == name).firstOrNull;
}
