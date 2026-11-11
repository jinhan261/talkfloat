#!/usr/bin/env python3
"""Generate one reviewed Sparkle release item; the private key stays in Keychain.

Run only after notarization/stapling. Upload the unchanged asset before publishing
this feed. A feed intentionally containing only a prerelease is a preview channel.
"""
import argparse
import base64
import email.utils
import re
from pathlib import Path
from urllib.parse import urlparse
import xml.etree.ElementTree as ET

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('asset', type=Path)
    p.add_argument('--version', required=True)
    p.add_argument('--build', required=True, type=int)
    p.add_argument('--url', required=True)
    p.add_argument('--signature', required=True)
    p.add_argument('--output', type=Path, default=Path('docs/updates/appcast.xml'))
    p.add_argument('--test-local', action='store_true', help='Allow loopback URL for a local upgrade test only')
    a = p.parse_args()
    u = urlparse(a.url)
    if not re.fullmatch(r'\d+(?:\.\d+){1,3}', a.version) or a.build <= 0:
        p.error('Use a numeric release version and positive build number.')
    valid_url = u.scheme == 'https' and u.netloc == 'github.com' and u.path.startswith('/jinhan261/talkfloat/releases/download/')
    if not valid_url and not (a.test_local and u.scheme == 'http' and u.hostname == '127.0.0.1'):
        p.error('Use the fixed GitHub release asset URL, or explicitly opt into a loopback test.')
    if not a.asset.is_file() or a.asset.suffix not in {'.dmg', '.zip'}:
        p.error('Expected an existing signed DMG or ZIP.')
    try:
        if len(base64.b64decode(a.signature, validate=True)) != 64:
            raise ValueError()
    except (ValueError, base64.binascii.Error):
        p.error('Expected a 64-byte Ed25519 signature encoded as base64.')
    root = ET.Element('rss', version='2.0')
    channel = ET.SubElement(root, 'channel')
    ET.SubElement(channel, 'title').text = 'TalkFloat Preview Updates'
    ET.SubElement(channel, 'link').text = 'https://github.com/jinhan261/talkfloat'
    ET.SubElement(channel, 'description').text = 'Signed TalkFloat releases for Apple Silicon.'
    ET.SubElement(channel, 'language').text = 'zh-cn'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'TalkFloat {a.version}'
    ET.SubElement(item, 'pubDate').text = email.utils.formatdate(usegmt=True)
    ET.SubElement(item, f'{{{SPARKLE}}}version').text = str(a.build)
    ET.SubElement(item, f'{{{SPARKLE}}}shortVersionString').text = a.version
    ET.SubElement(item, f'{{{SPARKLE}}}minimumSystemVersion').text = '14.2'
    ET.SubElement(item, 'description').text = '首次设置与声音测试；独立设置窗口；安全更新；更轻量的菜单和字幕。安装前请结束并保存当前会话。本地模型仍要求 macOS 26.4+。'
    ET.SubElement(item, 'enclosure', url=a.url, length=str(a.asset.stat().st_size), type='application/octet-stream', **{f'{{{SPARKLE}}}edSignature': a.signature, f'{{{SPARKLE}}}os':'macos'})
    ET.indent(root, space='  ')
    a.output.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(root).write(a.output, encoding='utf-8', xml_declaration=True)
    print(a.output)

if __name__ == '__main__':
    main()
