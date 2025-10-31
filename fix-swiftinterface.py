#!/usr/bin/env python3
"""
Fix TangemSdk swiftinterface files by removing TangemSdk. prefixes from type references
This resolves the module/class name collision where Swift interprets TangemSdk as the class
instead of the module when parsing fully qualified type names.
"""

import os
import re
import sys
from pathlib import Path

def fix_swift_interface(file_path):
    """Fix a single swiftinterface file by removing TangemSdk. prefixes"""
    print(f"Processing: {file_path}")
    
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"  ERROR: Could not read file: {e}")
        return False
    
    original_content = content
    
    # Fix extension declarations: extension TangemSdk.TangemSdk -> extension TangemSdk
    content = re.sub(r'\bextension\s+TangemSdk\.TangemSdk\b', 'extension TangemSdk', content)
    
    # Replace TangemSdk.TangemSdk type references with TangemSdk (unqualified)
    # Since we're already in the TangemSdk module, we don't need the module qualifier
    content = re.sub(r'\bTangemSdk\.TangemSdk\b', 'TangemSdk', content)
    
    # Replace all TangemSdk.TypeName with TypeName
    # The regex \bTangemSdk\.([A-Z]...) ensures we only match module-qualified types
    # and won't match standalone "TangemSdk" in imports or class declarations
    content = re.sub(r'\bTangemSdk\.([A-Z][a-zA-Z0-9_]+)\b', r'\1', content)
    
    # Check if anything changed
    if content != original_content:
        try:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            print("  ✓ Fixed")
            return True
        except Exception as e:
            print(f"  ERROR: Could not write file: {e}")
            return False
    else:
        print("  - No changes needed")
        return True

def main():
    # Find all swiftinterface files in the XCFramework
    script_dir = Path(__file__).parent
    framework_path = script_dir / 'Multisig' / 'Logic' / 'Tangem' / 'TangemSdk.xcframework'
    
    if not framework_path.exists():
        print(f"ERROR: Framework not found at {framework_path}")
        sys.exit(1)
    
    # Recursively find all .swiftinterface files
    files = list(framework_path.rglob('*.swiftinterface'))
    
    if not files:
        print("ERROR: No swiftinterface files found")
        sys.exit(1)
    
    print(f"Found {len(files)} swiftinterface file(s)\n")
    
    fixed = 0
    failed = 0
    
    for file in files:
        if fix_swift_interface(str(file)):
            fixed += 1
        else:
            failed += 1
    
    print("\nSummary:")
    print(f"  Fixed: {fixed}")
    print(f"  Failed: {failed}")
    print(f"  Total: {len(files)}")
    
    sys.exit(1 if failed > 0 else 0)

if __name__ == '__main__':
    main()

