"""Tạo Sources/Assets.xcassets từ ảnh trong res/ (biểu tượng app, logo màn hình chờ, màu nền)."""
import json, os, shutil
root = os.path.dirname(os.path.abspath(__file__))
cat = os.path.join(root, 'Sources', 'Assets.xcassets')
shutil.rmtree(cat, ignore_errors=True)
def w(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f: json.dump(data, f, indent=2)
info = {'author': 'xcode', 'version': 1}
w(os.path.join(cat, 'Contents.json'), {'info': info})
icon = os.path.join(cat, 'AppIcon.appiconset')
w(os.path.join(icon, 'Contents.json'), {'images': [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}], 'info': info})
shutil.copy(os.path.join(root, 'res', 'AppIcon.png'), os.path.join(icon, 'AppIcon.png'))
logo = os.path.join(cat, 'LaunchLogo.imageset')
w(os.path.join(logo, 'Contents.json'), {'images': [{'filename': 'LaunchLogo.png', 'idiom': 'universal', 'scale': '3x'}], 'info': info})
shutil.copy(os.path.join(root, 'res', 'LaunchLogo.png'), os.path.join(logo, 'LaunchLogo.png'))
def color(name, r, g, b):
    w(os.path.join(cat, name + '.colorset', 'Contents.json'), {'colors': [{'idiom': 'universal', 'color': {'color-space': 'srgb', 'components': {'red': '0x%02X' % r, 'green': '0x%02X' % g, 'blue': '0x%02X' % b, 'alpha': '1.000'}}}], 'info': info})
color('LaunchBackground', 0x17, 0x10, 0x2E)
color('AccentColor', 0x8A, 0x3B, 0xFF)
print('Assets.xcassets ok')
