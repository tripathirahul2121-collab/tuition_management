import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  static TextStyle get title => TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static TextStyle get heading => TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const body = TextStyle(fontSize: 16, color: AppColors.textSecondary);

  static const button = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
}
