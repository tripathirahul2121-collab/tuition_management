import 'dart:io';

import 'package:image/image.dart' as img;

const _size = 1024;

void _writePng(String path, img.Image source, int size) {
  final file = File(path)..createSync(recursive: true);
  final image = img.copyResize(
    source,
    width: size,
    height: size,
    interpolation: img.Interpolation.cubic,
  );
  file.writeAsBytesSync(img.encodePng(image));
}

void main(List<String> args) {
  const sourcePath = 'assets/icon/me_classes_app_icon.png';
  final inputPath = args.isEmpty ? sourcePath : args.first;
  final inputBytes = File(inputPath).readAsBytesSync();
  final decoded = img.decodeImage(inputBytes);

  if (decoded == null) {
    throw StateError('Could not decode icon image at $inputPath');
  }

  final icon = img.copyResize(
    img.bakeOrientation(decoded),
    width: _size,
    height: _size,
    interpolation: img.Interpolation.cubic,
  );

  _writePng(sourcePath, icon, 1024);

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

  final windowsIcon = File('windows/runner/resources/app_icon.ico')
    ..createSync(recursive: true);
  final windowsIconImage = img.copyResize(
    icon,
    width: 256,
    height: 256,
    interpolation: img.Interpolation.cubic,
  );
  windowsIcon.writeAsBytesSync(img.encodeIco(windowsIconImage));

  _writePng('web/favicon.png', icon, 32);
  _writePng('web/icons/Icon-192.png', icon, 192);
  _writePng('web/icons/Icon-maskable-192.png', icon, 192);
  _writePng('web/icons/Icon-512.png', icon, 512);
  _writePng('web/icons/Icon-maskable-512.png', icon, 512);
}
