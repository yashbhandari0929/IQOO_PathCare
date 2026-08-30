import re

def fix_file(filepath, fixes):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    for fix in fixes:
        if fix['type'] == 'unused_import':
            # Remove line containing the import
            content = re.sub(r"import\s+['\"].*?" + fix['name'] + r"['\"];\n?", "", content)
        elif fix['type'] == 'unused_local':
            # Regex to find and remove the local variable declaration (simple cases)
            var_name = fix['name']
            content = re.sub(r"^\s*(?:final|var|int|String|double|bool|DateTime|dynamic)[\s\w<,>]*\s+" + var_name + r"\s*(?:=[^;]+)?;\n?", "", content, flags=re.MULTILINE)
        elif fix['type'] == 'unnecessary_null_comparison':
            # e.g., if (foo != null) -> if (true) or just remove
            pass
        elif fix['type'] == 'unnecessary_type_check':
            pass
        elif fix['type'] == 'deprecated_scale':
            content = content.replace('.scale(', '.scaleByDouble(')
        elif fix['type'] == 'deprecated_opacity':
            content = re.sub(r'\.withOpacity\(([^)]+)\)', r'.withValues(alpha: \1)', content)
            
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

fixes = {
    r"lib\screens\patient\chatbot_screen.dart": [
        {'type': 'unused_import', 'name': 'http.dart'},
        {'type': 'unused_import', 'name': 'http_parser.dart'}
    ],
    r"lib\widgets\queue_status_widget.dart": [
        {'type': 'unused_import', 'name': 'navigation_service.dart'}
    ],
    r"lib\screens\patient\hospital_navigation_screen.dart": [
        {'type': 'unused_local', 'name': 'roomNumber'}
    ],
    r"lib\screens\patient\patient_appointments_screen.dart": [
        {'type': 'unused_local', 'name': 'today'},
        {'type': 'unused_local', 'name': 'appointmentDate'}
    ],
    r"lib\services\booking_service.dart": [
        {'type': 'unused_local', 'name': 'completedCount'}
    ],
    r"lib\services\navigation_service.dart": [
        {'type': 'unused_local', 'name': 't'}
    ],
    r"lib\widgets\floor_map_widget.dart": [
        {'type': 'unused_local', 'name': 'height'}
    ],
    r"lib\widgets\interactive_floor_map.dart": [
        {'type': 'deprecated_scale', 'name': ''}
    ],
    r"lib\screens\admin\admin_dashboard.dart": [
        {'type': 'unused_local', 'name': 'result'}
    ]
}

for filepath, fix_list in fixes.items():
    try:
        fix_file(filepath, fix_list)
        print(f"Fixed {filepath}")
    except Exception as e:
        print(f"Failed {filepath}: {e}")
