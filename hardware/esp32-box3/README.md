# Adam BOX-3

USB firmware for ESP32-S3-BOX-3, with a touch **Talk** button, microphone capture with end-of-speech detection, speaker playback, and live sensor display. The device updates temperature/humidity and radar signal every second without a Mac process. Talk is enabled during a host connection. The Mac bridge uses the existing `api/physical` runtime and voice providers. Without a host it also works on its own over Wi-Fi as a paired Adam display with a microphone (see below). There is no wake word: tap Talk.

Firmware uses Espressif's [BOX-3 BSP](https://components.espressif.com/components/espressif/esp-box-3/versions/3.2.0). `i2c_bus` is pinned to 1.2.0 because later releases require an API absent in the installed base ESP-IDF v5.3. Dependencies are locked in `dependencies.lock`.

```sh
source ~/esp/esp-idf/export.sh
cd hardware/esp32-box3
idf.py build
idf.py -p /dev/cu.usbmodemXXXX flash
```

Run from the repository root with Node 26+, ffmpeg, pyserial, and the existing `.env` provider credentials:

```sh
python3 hardware/esp32-box3/bridge.py --turns 3 --wait 120
```

Each tap records until roughly 0.9 seconds of quiet after speech, with a 15-second limit. If no speech starts, recording stops after four seconds. Energy thresholds adapt to the measured background level; this is a bounded energy detector, not a speech model. Only the captured clip is sent to transcription. Raw clips and reply audio live in a temporary directory removed when the bridge exits. Transcriptions, conversation turns, and capture provenance persist in the ignored `data/box3/runtime.sqlite`. Per-device credentials are local files with mode 0600. The bridge validates the USB vendor, serial identity, and firmware handshake; this is a trusted local USB setup, not remote device attestation.

Standalone replies start playing with a 128 ms PCM buffer while the HTTP response is still being read. The entire reply is no longer accumulated on the box. The backend still transcribes, reasons, and generates speech before sending its response, so that server wait remains. Failed HTTP responses are never played as audio; fragmented PCM is reassembled into complete samples, and codec failures fail the turn.

Every voice turn reads a fresh sensor snapshot into the existing physical context before asking the agent. Device acceleration/rotation are separate from radar room-movement signals. No radar signal is never projected into an empty-room claim. Unavailable or stale environmental data are excluded. The BOX bridge allows 35 seconds for TTS unless configured otherwise; the shared voice provider's default is unchanged.

```sh
python3 hardware/esp32-box3/bridge.py --sensors --seconds 30
python3 hardware/esp32-box3/bridge.py --ask 'In 40 words, describe the current sensor readings.'
python3 hardware/esp32-box3/check.py
python3 hardware/esp32-box3/check.py --capture --network --output data/box3/check.json
```

`check.py` exits nonzero when a sensor or the microphone task is unavailable. `--capture` checks a variable-length recording; provide an audible test phrase during the recording. `--network` also requires a Wi-Fi connection. The USB `Q` status includes task startup, internal memory, the latest Wi-Fi disconnect reason, and the latest standalone voice HTTP status/audio length. `captureMs`, `firstAudioMs`, `turnMs`, and `captureBytes` measure the most recent standalone turn from the recording request. It never returns Wi-Fi passwords or display tokens.

Portable audio tests cover pause handling, silence/noise, recording limits, fragmented PCM, playback before the response ends, malformed samples, and speaker errors:

```sh
cc -std=c11 -O2 -Wall -Wextra -Werror hardware/esp32-box3/test_audio.c hardware/esp32-box3/main/voice_endpoint.c hardware/esp32-box3/main/pcm_stream.c -lm -o /tmp/adam-box3-test-audio
/tmp/adam-box3-test-audio
```

Wi-Fi and TLS buffers use external RAM, and the microphone task has a 16 KB stack for the audio buffers and alarm FFT. Without external Wi-Fi allocations, internal RAM can run out before the microphone and temperature/humidity event loop start. An 8 KB microphone stack is insufficient once the detector runs. TLS allocations in internal RAM can fail with `0x7F00` even after Wi-Fi connects. SNTP synchronizes the device clock for HTTPS certificate-date verification; HTTPS requests wait up to 15 seconds for initial clock synchronization.

The SDK's SSID and password arrays are fixed-width fields: a 32-byte SSID and a 64-byte key occupy the entire field. Their bounded, validated contents are copied without reserving a terminator in those SDK fields. Reserving one byte silently truncates a maximum-length network name and produces a misleading access-point-not-found error. USB `W` scans nearby Wi-Fi networks for setup diagnostics.

Sensors verified on 2026-10-05: IMU ID 0x60, live acceleration/rotation, nearby temperature approximately 26.4–26.6°C, humidity approximately 55–56%, and AT581x radar configuration readback at dock address 0x28. The temperature/humidity device responds at 0x38. The 45-second radar test stayed low; controlled movement detection has not yet been demonstrated. Infrared and Wi-Fi CSI remain untested on this firmware.

The base ESP-IDF v5.3 lacks a public bus lookup, and BSP 3.2 exposes only its main I2C handle. A linker wrapper observes the real `i2c_new_master_bus` call to retain the dock handle, preserving the driver's behavior. AT581x register settings follow Espressif's [driver defaults](https://github.com/espressif/esp-iot-solution/blob/master/components/sensors/radar/at581x/at581x.c); they are not calibrated range or person-count measurements.

The transport is `ADAM`, a one-byte frame type, little-endian uint32 byte length, then payload. `H` handshakes, `D` ends a host session, `P` requests/returns a sensor JSON snapshot, `R` requests capture, `A` returns mono PCM16 at 16 kHz, `S` plays that format, `K` acknowledges codec completion, `T` updates the display, and `E` reports an error. The maximum payload is 30 seconds of audio. A speaker acknowledgement proves codec completion, not that a person heard sound.

The original 16 MB flash backup is `data/box3/factory-backup.bin`. Restore only to the same physical device:

```sh
python -m esptool --chip esp32s3 -p /dev/cu.usbmodem2101 write_flash 0 data/box3/factory-backup.bin
```

The bridge exits after the requested number of turns or timeout and closes its serial port. Firmware remains on the device. The USB bridge does not provision credentials; standalone setup stores Wi-Fi details and a display-scoped token on the box, never provider API keys.

## Standalone over Wi-Fi (paired display)

The box pairs to the Adam backend as an ordinary paired display, so it gets the same rules as any screen: it can talk to Adam but can never approve or cancel anything (those words, or a waiting approval, send you to your phone).

1. In the Adam app, open Your Home and add a display. It shows a link and a one-time code.
2. Run the backend where the box can reach it, for example `npm start` on the Mac (the box talks to `http://<mac address>:3000`).
3. With the box plugged into the Mac: `python3 hardware/esp32-box3/provision.py`. It asks for the server address, Wi-Fi name and password, the link and the code (password and code are hidden). It redeems the pairing on the server and stores Wi-Fi, address and the display's own token in the box's flash, then the box restarts and shows "Online".
4. Tap Talk: speak, pause to finish, and the captured clip is sent to `POST /display/:id/voice`. Adam's spoken answer plays as it downloads. Room readings go to `/display/:id/sensors` every minute and before each voice question, and are added to room questions only.

An always-on microphone task runs the smoke/CO beep-pattern detector from `firmware/alarm-pattern/` (not neural; no learned sounds run on the box). A detection goes to `/display/:id/sound`, which raises it as an urgent household event, and is also sent over USB as a `B` frame while a bridge is connected. The detector is paused while the speaker is playing.

Routes and their rules are in `api/services/box-gateway.js` and `test/smoke/box-gateway.test.js`. Partition table: `partitions.csv` (3 MB app). Startup checkpoints are sent as `D` frames, which the bridge ignores.

For a box already paired with a protected local `data/box3/provisioned-config.json`, update its network without repeating account pairing:

```sh
python3 hardware/esp32-box3/wifi_setup.py --ssid 'Your 2.4 GHz network' --dialog
python3 hardware/esp32-box3/check.py --network
```

On macOS, `--dialog` opens a hidden password field. Omit `--ssid` to enter the network name in a dialog too. Without `--dialog`, the password is read hidden in the terminal. The local setup file and flash backups contain credentials; keep them private. Wi-Fi disconnect reason 201 means the configured access point was not found. A successful Wi-Fi connection alone does not prove the backend accepted a voice request; check the standalone voice status after a Talk turn. Each network voice turn posts fresh room readings before asking Adam. Sending USB `R` after `D` exercises the same standalone recording/request path as the Talk button; while a USB host session is connected, `R` returns audio to the host instead.

Verified 2026-10-08 on the bench: Wi-Fi-free USB handshake, 8 s recording, IMU readings, and a synthetic three-beep smoke pattern played from the Mac speaker was reported as `smoke_alarm`. Not yet verified: the Wi-Fi and pairing path end to end, a real alarm, and the sensor base (it was not detected this session: no 0x28/0x38 devices, and its setup blocks, so it now runs in its own task).

Verified 2026-11-04 on device `80456b649200`: live account enrollment, persistent Wi-Fi/live-backend provisioning, IMU, fresh temperature/humidity, radar register readback, complete microphone capture, USB voice transcription/reply/playback acknowledgement, and standalone HTTPS voice through the live backend. The standalone test returned HTTP 200 and 184000 PCM audio bytes; backend logs independently recorded HTTP 200 for sensor uploads and 256000-byte voice requests. Clock synchronization and TLS reported no error. The device photo also showed a movement signal. Controlled radar coverage, infrared, real alarm detection, and person-confirmed speaker audibility remain separate checks. The hardware does not need a running Mac bridge for Wi-Fi Talk.

Latency pass on 2026-11-04: the short-phrase USB capture finished in 4.45 seconds instead of 8.30, roughly 0.73 seconds after the test phrase ended. A longer capture transcribed “Please check the room temperature and humidity.” exactly in 4.704 seconds of audio. Same-phrase standalone tests measured first playback at 26.304 seconds before and 21.722 seconds after, with HTTP 200 and streamed PCM playback. These are individual live measurements, not a latency guarantee; server inference and speech generation still vary.
