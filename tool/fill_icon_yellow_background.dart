import 'dart:io';

import 'package:image/image.dart' as img;

const _masterIconPath = 'assets/icon/me.png';

void _writePng(String path, img.Image source, int size) {
  final image = img.copyResize(
    source,
    width: size,
    height: size,
    interpolation: img.Interpolation.cubic,
  );
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
}

bool _isWhiteBackground(img.Pixel pixel) {
  final r = pixel.r.toInt();
  final g = pixel.g.toInt();
  final b = pixel.b.toInt();
  final maxChannel = [r, g, b].reduce((a, b) => a > b ? a : b);
  final minChannel = [r, g, b].reduce((a, b) => a < b ? a : b);

  return minChannel > 218 && maxChannel - minChannel < 30;
}

void main() {
  final inputBytes = File(_masterIconPath).readAsBytesSync();
  final decoded = img.decodeImage(inputBytes);
  if (decoded == null) {
    throw StateError('Could not decode $_masterIconPath');
  }

  final icon = img.bakeOrientation(decoded);
  final yellowSample = icon.getPixel(
    icon.width ~/ 2,
    (icon.height * 0.08).round(),
  );
  final fill = img.ColorRgb8(
    yellowSample.r.toInt(),
    yellowSample.g.toInt(),
    yellowSample.b.toInt(),
  );
  final centerX = (icon.width - 1) / 2;
  final centerY = (icon.height - 1) / 2;
  final outerRadius = (icon.width < icon.height ? icon.width : icon.height) / 2;

  for (final pixel in icon) {
    final dx = pixel.x - centerX;
    final dy = pixel.y - centerY;
    final isOuterEdge =
        dx * dx + dy * dy > (outerRadius - 6) * (outerRadius - 6);

    if (_isWhiteBackground(pixel) || isOuterEdge) {
      pixel
        ..r = fill.r
        ..g = fill.g
        ..b = fill.b;
    }
  }

  File(_masterIconPath).writeAsBytesSync(img.encodePng(icon));

  final androidIcons = {
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
    'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
  };

  for (final entry in androidIcons.entries) {
    _writePng(entry.key, icon, entry.value);
  }

  final iosIcons = {
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png': 20,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png': 40,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png': 60,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png': 29,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png': 58,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png': 87,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png': 40,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png': 80,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png': 120,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png': 120,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png': 180,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png': 76,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png': 152,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png':
        167,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png':
        1024,
  };

  for (final entry in iosIcons.entries) {
    _writePng(entry.key, icon, entry.value);
  }

  final macosIcons = {
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png': 16,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png': 32,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png': 64,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png': 128,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png': 256,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png': 512,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png': 1024,
  };

  for (final entry in macosIcons.entries) {
    _writePng(entry.key, icon, entry.value);
  }

  final windowsIconImage = img.copyResize(
    icon,
    width: 256,
    height: 256,
    interpolation: img.Interpolation.cubic,
  );
  File('windows/runner/resources/app_icon.ico')
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodeIco(windowsIconImage));

  _writePng('web/favicon.png', icon, 32);
  _writePng('web/icons/Icon-192.png', icon, 192);
  _writePng('web/icons/Icon-maskable-192.png', icon, 192);
  _writePng('web/icons/Icon-512.png', icon, 512);
  _writePng('web/icons/Icon-maskable-512.png', icon, 512);
}
