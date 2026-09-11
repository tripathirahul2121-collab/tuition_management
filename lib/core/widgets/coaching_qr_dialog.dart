import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_branding.dart';
import '../linking/public_app_link.dart';
import 'branded_logo.dart';

Future<void> showCoachingQrDialog({
  required BuildContext context,
  required AppBranding branding,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => CoachingQrSheet(branding: branding),
  );
}

class CoachingQrSheet extends StatelessWidget {
  const CoachingQrSheet({required this.branding, super.key});

  final AppBranding branding;

  @override
  Widget build(BuildContext context) {
    final publicLink = PublicAppLink.validate(branding.publicAppUrl);
    final uri = publicLink.uri;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final qrSize = screenWidth < 360
        ? 220.0
        : screenWidth < 520
        ? 240.0
        : 260.0;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height - 32,
                ),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: branding.surfaceColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 34,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: 'Close QR dialog',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                      BrandedLogo(branding: branding, size: 64),
                      const SizedBox(height: 14),
                      Text(
                        'Scan to Open Our App',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: branding.textColor,
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        uri == null
                            ? publicLink.errorMessage!
                            : 'Scan this QR using your phone camera.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (uri == null)
                        _InvalidLinkBox(
                          message: publicLink.errorMessage!,
                          branding: branding,
                        )
                      else
                        _ScannableQrCode(
                          url: uri.toString(),
                          branding: branding,
                          size: qrSize,
                        ),
                      const SizedBox(height: 18),
                      if (uri != null)
                        SelectableText(
                          uri.toString(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: branding.primaryColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      const SizedBox(height: 18),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _DialogActionButton(
                            icon: Icons.copy_rounded,
                            label: 'Copy Link',
                            onPressed: uri == null
                                ? null
                                : () => copyPublicAppLink(context, branding),
                          ),
                          _DialogActionButton(
                            icon: Icons.open_in_new_rounded,
                            label: 'Open',
                            onPressed: uri == null
                                ? null
                                : () => openPublicAppLink(context, branding),
                          ),
                          _DialogActionButton(
                            icon: Icons.ios_share_rounded,
                            label: 'Share',
                            onPressed: uri == null
                                ? null
                                : () => sharePublicAppLink(context, branding),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScannableQrCode extends StatelessWidget {
  const _ScannableQrCode({
    required this.url,
    required this.branding,
    required this.size,
  });

  final String url;
  final AppBranding branding;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'QR code for ${branding.instituteName} app link',
      image: true,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: QrImageView(
          key: ValueKey('coaching-qr:$url'),
          data: url,
          version: QrVersions.auto,
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          size: size,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Color(0xFF111827),
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Color(0xFF111827),
          ),
        ),
      ),
    );
  }
}

class _InvalidLinkBox extends StatelessWidget {
  const _InvalidLinkBox({required this.message, required this.branding});

  final String message;
  final AppBranding branding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: branding.primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF78350F),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogActionButton extends StatelessWidget {
  const _DialogActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size(124, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    );
  }
}

Future<void> copyPublicAppLink(
  BuildContext context,
  AppBranding branding,
) async {
  final publicLink = PublicAppLink.validate(branding.publicAppUrl);
  final uri = publicLink.uri;
  if (uri == null) {
    _showSnack(context, publicLink.errorMessage!);
    return;
  }

  await Clipboard.setData(ClipboardData(text: uri.toString()));
  if (!context.mounted) return;
  _showSnack(context, 'App link copied.');
}

Future<void> openPublicAppLink(
  BuildContext context,
  AppBranding branding,
) async {
  final publicLink = PublicAppLink.validate(branding.publicAppUrl);
  final uri = publicLink.uri;
  if (uri == null) {
    _showSnack(context, publicLink.errorMessage!);
    return;
  }

  final opened = await launchUrl(uri, webOnlyWindowName: '_blank');
  if (!opened && context.mounted) {
    _showSnack(context, 'Could not open the app link.');
  }
}

Future<void> sharePublicAppLink(
  BuildContext context,
  AppBranding branding,
) async {
  final publicLink = PublicAppLink.validate(branding.publicAppUrl);
  final uri = publicLink.uri;
  if (uri == null) {
    _showSnack(context, publicLink.errorMessage!);
    return;
  }

  try {
    await SharePlus.instance.share(
      ShareParams(
        subject: branding.instituteName,
        text: 'Join ${branding.instituteName}: $uri',
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    await copyPublicAppLink(context, branding);
    if (!context.mounted) return;
    _showSnack(context, 'Sharing is unavailable here, so the link was copied.');
  }
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
