#!/usr/bin/env python3
"""Check the connected BOX-3, with an optional bounded microphone recording."""
import argparse
import json
import math
import pathlib
import struct

from bridge import Box, find_port


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port')
    parser.add_argument('--capture', action='store_true')
    parser.add_argument('--network', action='store_true')
    parser.add_argument('--output', type=pathlib.Path)
    args = parser.parse_args()
    box = Box(args.port or find_port())
    report = {'deviceId': box.device_id, 'failures': []}
    try:
        for kind, key in [('Q', 'system'), ('P', 'sensors')]:
            box.send(kind)
            received, payload = box.receive(15)
            if received != kind:
                raise RuntimeError(f'Expected {kind}, received {received}')
            report[key] = json.loads(payload)
        if not report['system']['micTaskCreated']:
            report['failures'].append('Microphone task did not start')
        if args.network and not report['system']['wifiOnline']:
            report['failures'].append('Wi-Fi is offline')
        for sensor in ('imu', 'environment', 'radar'):
            if not report['sensors'][sensor]['available']:
                report['failures'].append(f'{sensor} unavailable')
        if args.capture:
            box.send('R')
            received, audio = box.receive(20)
            if received != 'A':
                raise RuntimeError('Microphone audio missing')
            samples = struct.unpack('<' + 'h' * (len(audio) // 2), audio)
            rms = math.sqrt(sum(n * n for n in samples) / max(len(samples), 1))
            report['microphone'] = {'bytes': len(audio), 'seconds': round(len(audio) / 32000, 3), 'rms': round(rms, 2), 'peak': max(map(abs, samples), default=0)}
            if not 12800 <= len(audio) <= 480000 or len(audio) % 2 or rms < 20:
                report['failures'].append('Microphone capture incomplete or silent')
    finally:
        try:
            box.send('D')
        finally:
            box.serial.close()
    if args.output:
        args.output.write_text(json.dumps(report, indent=2))
        args.output.chmod(0o600)
    print(json.dumps(report, indent=2))
    raise SystemExit(bool(report['failures']))


if __name__ == '__main__':
    main()
