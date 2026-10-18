#!/usr/bin/env python3
"""Build without modifying an installed app or using a saved signing identity."""
import argparse
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--team-id')
    parser.add_argument('--signing-identity')
    parser.add_argument('--bundle-id', default='com.liveaiusagewidget.app')
    parser.add_argument('--arch', choices=['arm64', 'x86_64'], default='arm64')
    args = parser.parse_args()
    if bool(args.team_id) != bool(args.signing_identity):
        parser.error('Provide both --team-id and --signing-identity, or neither for a compile-only build.')
    if not re.fullmatch(r'[A-Za-z0-9.-]+', args.bundle_id):
        parser.error('Invalid bundle identifier')
    if args.team_id and not re.fullmatch(r'[A-Z0-9]{10}', args.team_id):
        parser.error('Invalid team identifier')
    build = ROOT / 'build'
    app = build / 'Live AI Usage Widget.app'
    if app.exists():
        shutil.rmtree(app)
    extension = app / 'Contents/PlugIns/UsageWidget.appex'
    group = (args.team_id or 'UNSIGNED00') + '.' + args.bundle_id
    for folder in [app / 'Contents/MacOS', app / 'Contents/Resources', extension / 'Contents/MacOS', extension / 'Contents/Resources', build / 'module-cache']:
        folder.mkdir(parents=True, exist_ok=True)
    for folder, executable, bundle, kind in [(app, 'UsageWidget', args.bundle_id, 'APPL'),
                                            (extension, 'UsageWidgetExtension', args.bundle_id + '.widget', 'XPC!')]:
        info = dict(CFBundleDisplayName='Live AI Usage Widget', CFBundleName='Live AI Usage Widget', CFBundleExecutable=executable,
                    CFBundleIdentifier=bundle, CFBundlePackageType=kind, CFBundleVersion='31',
                    CFBundleShortVersionString='1.2.0', LSMinimumSystemVersion='14.0', UsageAppGroup=group)
        if kind == 'XPC!':
            info['NSExtension'] = {'NSExtensionPointIdentifier': 'com.apple.widgetkit-extension'}
        else:
            info.update(CFBundleIconFile='LiveAIUsageWidget.icns', NSPrincipalClass='NSApplication', LSUIElement=True, CFBundleURLTypes=[{'CFBundleURLSchemes': ['live-ai-usage-widget']}])
        (folder / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        entitlement = {'com.apple.security.application-groups': [group]}
        if kind == 'XPC!':
            entitlement['com.apple.security.app-sandbox'] = True
        entitlements = build / (executable + '.entitlements')
        entitlements.write_bytes(plistlib.dumps(entitlement))
        command = ['xcrun', 'swiftc', '-O', '-parse-as-library', '-target', args.arch + '-apple-macosx14.0',
                   '-module-cache-path', str(build / 'module-cache')]
        if kind == 'XPC!':
            command += ['-application-extension', '-Xlinker', '-e', '-Xlinker', '_NSExtensionMain',
                        # The widget's refresh button is an App Intent, which needs these to build its metadata.
                        '-wmo', '-module-name', 'UsageWidgetExtension', '-emit-const-values-path', str(build / 'widget.swiftconstvalues'),
                        '-Xfrontend', '-const-gather-protocols-file', '-Xfrontend', str(intent_protocols(build))]
        command += [str(f) for f in sorted((ROOT / 'Shared').glob('*.swift'))]
        if kind == 'APPL':
            command += [str(ROOT / 'Helper/Reader.swift'), str(ROOT / 'Helper/Collector.swift')]
        if kind == 'APPL':
            command += [str(ROOT / 'Helper/Updater.swift'), str(ROOT / 'Helper/Diagnostics.swift')]
        command += [str(ROOT / ('App/UsageApp.swift' if kind == 'APPL' else 'Widget/UsageWidget.swift')),
                    '-o', str(folder / 'Contents/MacOS' / executable)]
        subprocess.run(command, check=True)
        if kind == 'XPC!':
            intent_metadata(build, extension, args.arch)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(build / 'module-cache'), str(ROOT / 'Tools/RenderIcon.swift'), '-o', str(build / 'render-icon')], check=True)
    subprocess.run([str(build / 'render-icon'), str(build / 'LiveAIUsageWidget.iconset')], check=True)
    subprocess.run(['iconutil', '-c', 'icns', str(build / 'LiveAIUsageWidget.iconset'), '-o', str(app / 'Contents/Resources/LiveAIUsageWidget.icns')], check=True)
    if args.signing_identity:
        for folder, executable in [(extension, 'UsageWidgetExtension'), (app, 'UsageWidget')]:
            subprocess.run(['codesign', '--force', '--options', 'runtime', '--timestamp', '--sign', args.signing_identity,
                            '--entitlements', str(build / (executable + '.entitlements')), str(folder)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    print(app)
    if not args.signing_identity:
        print('COMPILE-ONLY: this is not an installable signed distribution. Shared-container/widget registration is unverified.')


def intent_protocols(build):
    path = build / 'intent-protocols.json'
    path.write_text('["AppIntent","EntityQuery","AppEntity","TransientEntity","AppEnum","AppShortcutProviding",'
                    '"AppShortcutsProvider","AnyResolverProviding","AppIntentsPackage","DynamicOptionsProvider","WidgetConfigurationIntent"]')
    return path


def intent_metadata(build, extension, arch):
    """Writes Metadata.appintents into the widget, as Xcode would, so its intent button works."""
    sources = build / 'widget-sources.txt'
    sources.write_text('\n'.join(str(f) for f in sorted((ROOT / 'Shared').glob('*.swift')) + [ROOT / 'Widget/UsageWidget.swift']))
    values = build / 'widget-constvalues.txt'
    values.write_text(str(build / 'widget.swiftconstvalues'))
    version = re.search(r'Build version (\S+)', subprocess.run(['xcodebuild', '-version'], capture_output=True, text=True).stdout)
    toolchain = Path(subprocess.run(['xcrun', '--find', 'swiftc'], capture_output=True, text=True, check=True).stdout.strip()).parents[2]
    sdk = subprocess.run(['xcrun', '--show-sdk-path'], capture_output=True, text=True, check=True).stdout.strip()
    subprocess.run(['xcrun', 'appintentsmetadataprocessor', '--output', str(extension / 'Contents/Resources'), '--toolchain-dir', str(toolchain),
                    '--module-name', 'UsageWidgetExtension', '--sdk-root', sdk, '--xcode-version', version.group(1) if version else '17F113',
                    '--platform-family', 'macOS', '--deployment-target', '14.0', '--target-triple', arch + '-apple-macosx14.0',
                    '--source-file-list', str(sources), '--swift-const-vals-list', str(values),
                    '--binary-file', str(extension / 'Contents/MacOS/UsageWidgetExtension'), '--quiet-warnings'], check=True, capture_output=True)
    if not (extension / 'Contents/Resources/Metadata.appintents').exists():
        raise SystemExit('Widget intent metadata was not produced')


if __name__ == '__main__':
    main()
