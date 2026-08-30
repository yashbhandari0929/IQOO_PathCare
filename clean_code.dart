import 'dart:io';

void main() async {
  final libDir = Directory('lib');
  final files = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (f) => f.path.endsWith('.dart') && !f.path.contains('clean_code.dart'),
      );

  for (var file in files) {
    String content = await file.readAsString();
    bool modified = false;

    // Remove single line print statements
    final printRegex = RegExp(r'^\s*print\(.*?\);\s*$', multiLine: true);
    if (printRegex.hasMatch(content)) {
      content = content.replaceAll(printRegex, '');
      modified = true;
    }

    // Remove multi-line print statements
    final multiLinePrintRegex = RegExp(r'print\([\s\S]*?\);');
    if (multiLinePrintRegex.hasMatch(content)) {
      content = content.replaceAll(multiLinePrintRegex, '');
      modified = true;
    }

    // Remove unused imports (as seen in flutter analyze logs)
    // "warning - Unused import: '../services/navigation_service.dart' - lib\widgets\queue_status_widget.dart"
    if (file.path.contains('queue_status_widget.dart')) {
      final importRegex = RegExp(
        r"import '\.\./services/navigation_service\.dart';\n",
      );
      if (importRegex.hasMatch(content)) {
        content = content.replaceAll(importRegex, '');
        modified = true;
      }
    }

    // Replace withOpacity with withValues to fix deprecation warnings
    if (content.contains('.withOpacity(')) {
      // example: Colors.black.withOpacity(0.5) -> Colors.black.withValues(alpha: 0.5)
      final opacityRegex = RegExp(r'\.withOpacity\(([^)]+)\)');
      content = content.replaceAllMapped(opacityRegex, (match) {
        return '.withValues(alpha: ${match.group(1)})';
      });
      modified = true;
    }

    // Unnecessary dev dependency in pubspec.yaml
    // "warning - The dev dependency on flutter_launcher_icons is unnecessary because there is also a normal dependency on that package - pubspec.yaml"

    if (modified) {
      await file.writeAsString(content);
      print('Cleaned ${file.path}');
    }
  }

  // clean up pubspec.yaml
  final pubspecFile = File('pubspec.yaml');
  String pubspecContent = await pubspecFile.readAsString();
  final devDependencyRegex = RegExp(
    r'^\s*flutter_launcher_icons:.*$',
    multiLine: true,
  );
  // Check if it exists in dev_dependencies.
  // A safer approach: I will manually fix pubspec using tools if needed.
}
