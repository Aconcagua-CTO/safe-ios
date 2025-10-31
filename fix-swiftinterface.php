#!/usr/bin/env php
<?php
/**
 * Fix TangemSdk swiftinterface files by removing TangemSdk. prefixes from type references
 * This resolves the module/class name collision where Swift interprets TangemSdk as the class
 * instead of the module when parsing fully qualified type names.
 */

function fixSwiftInterface($filePath) {
    echo "Processing: $filePath\n";
    
    $content = file_get_contents($filePath);
    if ($content === false) {
        echo "  ERROR: Could not read file\n";
        return false;
    }
    
    $originalContent = $content;
    
    // Replace TangemSdk.TypeName with TypeName
    // But preserve:
    // - import statements: import TangemSdk (standalone, not TangemSdk.Something)
    // - Class declarations: final public class TangemSdk
    // - Self-reference: TangemSdk.TangemSdk (the class type itself)
    
    // Simple approach: Replace TangemSdk.TypeName with TypeName
    // The regex \bTangemSdk\.([A-Z]...) ensures we only match module-qualified types
    // and won't match standalone "TangemSdk" in imports or class declarations
    
    // Protect TangemSdk.TangemSdk (class self-reference) first
    $content = str_replace('TangemSdk.TangemSdk', '__TANGEMSDK_CLASS__', $content);
    
    // Replace all TangemSdk.TypeName with TypeName
    $content = preg_replace('/\bTangemSdk\.([A-Z][a-zA-Z0-9_]+)\b/', '$1', $content);
    
    // Restore TangemSdk.TangemSdk
    $content = str_replace('__TANGEMSDK_CLASS__', 'TangemSdk.TangemSdk', $content);
    
    // Check if anything changed
    if ($content !== $originalContent) {
        if (file_put_contents($filePath, $content) === false) {
            echo "  ERROR: Could not write file\n";
            return false;
        }
        echo "  ✓ Fixed\n";
        return true;
    } else {
        echo "  - No changes needed\n";
        return true;
    }
}

// Find all swiftinterface files in the XCFramework
$frameworkPath = __DIR__ . '/Multisig/Logic/Tangem/TangemSdk.xcframework';
$files = [];

if (!is_dir($frameworkPath)) {
    echo "ERROR: Framework not found at $frameworkPath\n";
    exit(1);
}

// Recursively find all .swiftinterface files
$iterator = new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator($frameworkPath)
);

foreach ($iterator as $file) {
    if ($file->isFile() && $file->getExtension() === 'swiftinterface') {
        $files[] = $file->getPathname();
    }
}

if (empty($files)) {
    echo "ERROR: No swiftinterface files found\n";
    exit(1);
}

echo "Found " . count($files) . " swiftinterface file(s)\n\n";

$fixed = 0;
$failed = 0;

foreach ($files as $file) {
    if (fixSwiftInterface($file)) {
        $fixed++;
    } else {
        $failed++;
    }
}

echo "\n";
echo "Summary:\n";
echo "  Fixed: $fixed\n";
echo "  Failed: $failed\n";
echo "  Total: " . count($files) . "\n";

exit($failed > 0 ? 1 : 0);

