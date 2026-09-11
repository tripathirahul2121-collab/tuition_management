import 'package:flutter/material.dart';

import '../linking/public_app_link.dart';

class AppBranding {
  const AppBranding({
    required this.instituteName,
    required this.instituteShortName,
    required this.tagline,
    required this.branchName,
    required this.logoAsset,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.textColor,
    required this.contactPhone,
    required this.whatsAppNumber,
    required this.supportEmail,
    required this.website,
    required this.publicAppUrl,
    required this.address,
    required this.footerText,
  });

  final String instituteName;
  final String instituteShortName;
  final String tagline;
  final String branchName;
  final String logoAsset;
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color textColor;
  final String contactPhone;
  final String whatsAppNumber;
  final String supportEmail;
  final String website;
  final String publicAppUrl;
  final String address;
  final String footerText;

  Uri? get publicAppUri {
    return PublicAppLink.validate(publicAppUrl).uri;
  }
}

class WhiteLabelConfig {
  static const AppBranding current = AppBranding(
    instituteName: String.fromEnvironment(
      'TUITION_INSTITUTE_NAME',
      defaultValue: 'Tuition Centre',
    ),
    instituteShortName: String.fromEnvironment(
      'TUITION_INSTITUTE_SHORT_NAME',
      defaultValue: 'Tuition',
    ),
    tagline: String.fromEnvironment(
      'TUITION_INSTITUTE_TAGLINE',
      defaultValue: 'Coaching centre management',
    ),
    branchName: String.fromEnvironment('TUITION_BRANCH_NAME'),
    logoAsset: String.fromEnvironment(
      'TUITION_LOGO_ASSET',
      defaultValue: 'assets/icon/melogo.png',
    ),
    primaryColor: Color.fromARGB(
      255,
      int.fromEnvironment('TUITION_PRIMARY_R', defaultValue: 63),
      int.fromEnvironment('TUITION_PRIMARY_G', defaultValue: 81),
      int.fromEnvironment('TUITION_PRIMARY_B', defaultValue: 181),
    ),
    secondaryColor: Color.fromARGB(
      255,
      int.fromEnvironment('TUITION_SECONDARY_R', defaultValue: 92),
      int.fromEnvironment('TUITION_SECONDARY_G', defaultValue: 107),
      int.fromEnvironment('TUITION_SECONDARY_B', defaultValue: 192),
    ),
    accentColor: Color.fromARGB(
      255,
      int.fromEnvironment('TUITION_ACCENT_R', defaultValue: 14),
      int.fromEnvironment('TUITION_ACCENT_G', defaultValue: 165),
      int.fromEnvironment('TUITION_ACCENT_B', defaultValue: 233),
    ),
    backgroundColor: Color(0xFFF6F8FC),
    surfaceColor: Colors.white,
    textColor: Color(0xFF111827),
    contactPhone: String.fromEnvironment('TUITION_CONTACT_PHONE'),
    whatsAppNumber: String.fromEnvironment('TUITION_WHATSAPP_NUMBER'),
    supportEmail: String.fromEnvironment('TUITION_SUPPORT_EMAIL'),
    website: String.fromEnvironment('TUITION_WEBSITE'),
    publicAppUrl: String.fromEnvironment(
      'TUITION_PUBLIC_APP_URL',
      defaultValue: 'https://tuition-backend.web.app',
    ),
    address: String.fromEnvironment('TUITION_ADDRESS'),
    footerText: String.fromEnvironment(
      'TUITION_FOOTER_TEXT',
      defaultValue: 'Built for focused coaching operations',
    ),
  );
}
