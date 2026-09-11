import 'package:flutter/material.dart';

import '../config/app_branding.dart';

class AppColors {
  // BRAND COLORS (Client-changeable)
  static Color get primary => WhiteLabelConfig.current.primaryColor;
  static Color get secondary => WhiteLabelConfig.current.secondaryColor;

  // BACKGROUNDS
  static Color get background => WhiteLabelConfig.current.backgroundColor;
  static Color get surface => WhiteLabelConfig.current.surfaceColor;

  // TEXT COLORS
  static Color get textPrimary => WhiteLabelConfig.current.textColor;
  static const textSecondary = Color(0xFF6E6E73);

  // STATUS COLORS
  static const success = Color(0xFF34C759);
  static const error = Color(0xFFFF3B30);
}
