#!/usr/bin/env python3
"""Generate signed GitHub Release attachments. Never uploads or publishes anything."""
import argparse, base64, pathlib, plistlib, re, subprocess, xml.etree.ElementTree as ET

p = argparse.ArgumentParser()
p.add_argument('--app', type=pathlib.Path, required=True)
p.add_argument('--archive', type=pathlib.Path, required=True)
p.add_argument('--key', type=pathlib.Path, required=True)
p.add_argument('--sign-tool', type=pathlib.Path, required=True)
a = p.parse_args()
info = plistlib.loads((a.app / 'Contents/Info.plist').read_bytes())
version, build = info['TokenMonitorReleaseVersion'], info['CFBundleVersion']
assert re.fullmatch(r'\d+\.\d+\.\d+(?:-beta\.[1-9]\d*)?', version)
assert re.fullmatch(r'[1-9]\d*', build)
assert info['CFBundleIdentifier'] == 'local.tokenmonitor.native.beta'
assert len(base64.b64decode(info['SUPublicEDKey'], validate=True)) == 32
# Prove the signing file matches the public key embedded in the app before generating any feed.
source = pathlib.Path(__file__).with_name('update-signing-key.swift')
public_file = pathlib.Path(__file__).resolve().parents[1] / 'Resources/UpdatePublicKey.txt'
assert info['SUPublicEDKey'] == public_file.read_text().strip()
subprocess.run(['swift', str(source), str(a.key), str(public_file)], check=True)
sig = subprocess.check_output([str(a.sign_tool), '--ed-key-file', str(a.key), '-p', str(a.archive)], text=True).strip()
assert len(base64.b64decode(sig, validate=True)) == 64
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', ns)
rss = ET.Element('rss', {'version': '2.0'})
channel = ET.SubElement(rss, 'channel')
ET.SubElement(channel, 'title').text = 'Token Monitor Native Updates'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = version
ET.SubElement(item, '{'+ns+'}version').text = build
ET.SubElement(item, '{'+ns+'}shortVersionString').text = version
ET.SubElement(item, '{'+ns+'}minimumSystemVersion').text = '26.0'
url = 'https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/download/v' + version + '/' + a.archive.name
ET.SubElement(item, 'enclosure', {'url': url, 'length': str(a.archive.stat().st_size), 'type': 'application/octet-stream', '{'+ns+'}edSignature': sig})
feed = a.archive.parent / 'appcast.xml'
ET.indent(rss)
ET.ElementTree(rss).write(feed, encoding='utf-8', xml_declaration=True)
subprocess.run([str(a.sign_tool), '--ed-key-file', str(a.key), str(feed)], check=True)
subprocess.run([str(a.sign_tool), '--ed-key-file', str(a.key), '--verify', str(feed)], check=True)
subprocess.run([str(a.sign_tool), '--ed-key-file', str(a.key), '--verify', str(a.archive), sig], check=True)
print('Signed appcast.xml and archive verified. Upload both only when publishing the matching release.')
