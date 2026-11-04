#!/usr/bin/env python3
"""Update Wi-Fi on an already paired BOX-3 without putting its password in chat or shell history."""
import argparse
import getpass
import json
import pathlib
import subprocess

from bridge import Box, ROOT, find_port


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ssid')
    parser.add_argument('--dialog', action='store_true', help='Use a hidden macOS password dialog')
    parser.add_argument('--config', type=pathlib.Path, default=ROOT / 'data/box3/provisioned-config.json')
    args = parser.parse_args()
    config = json.loads(args.config.read_text())
    if args.ssid:
        config['ssid'] = args.ssid
    elif args.dialog:
        result = subprocess.run([
            'osascript', '-e',
            'text returned of (display dialog "Enter the 2.4 GHz Wi-Fi network name for the BOX-3." '
            'default answer "" buttons {"Cancel", "Next"} default button "Next" with title "Adam BOX-3 Wi-Fi")'
        ], capture_output=True, text=True)
        if result.returncode:
            raise SystemExit('Wi-Fi setup cancelled; device settings were not changed.')
        config['ssid'] = result.stdout.rstrip('\n')
    else:
        config['ssid'] = input('2.4 GHz Wi-Fi name: ').strip()
    if not config['ssid'] or len(config['ssid'].encode()) > 32:
        raise SystemExit('Wi-Fi name must contain 1–32 bytes.')
    if args.dialog:
        result = subprocess.run([
            'osascript', '-e',
            'text returned of (display dialog "Enter the Wi-Fi password for the BOX-3. It will be stored on the box and in its protected local setup file." '
            'default answer "" with hidden answer buttons {"Cancel", "Connect"} default button "Connect" with title "Adam BOX-3 Wi-Fi")'
        ], capture_output=True, text=True)
        if result.returncode:
            raise SystemExit('Wi-Fi setup cancelled; device settings were not changed.')
        password = result.stdout.rstrip('\n')
    else:
        password = getpass.getpass('Wi-Fi password (hidden): ')
    if len(password.encode()) > 64:
        raise SystemExit('Wi-Fi password exceeds the device limit.')
    config['pass'] = password
    box = Box(find_port())
    try:
        box.send('C', json.dumps(config).encode())
        kind, _ = box.receive(15)
        if kind != 'K':
            raise RuntimeError('The BOX-3 did not accept the settings')
    finally:
        box.serial.close()
    args.config.chmod(0o600)
    args.config.write_text(json.dumps(config))
    print('Wi-Fi settings accepted. The BOX-3 is restarting.')


if __name__ == '__main__':
    main()
