#!/usr/bin/env python3
"""Records one scene of integration_test/demo_test.dart from the iOS simulator.
    python3 tools/record_scene.py health out.mp4 [device]
Starts the screen recording, runs the scene, stops, and trims the start-up so the video
begins when the app does."""
import os, signal, subprocess, sys, time
scene, out = sys.argv[1], sys.argv[2]
dev = sys.argv[3] if len(sys.argv) > 3 else open('/tmp/sim_id').read().strip()
subprocess.run(['xcrun', 'simctl', 'privacy', dev, 'grant', 'location', 'com.nolifa.app'], stderr=subprocess.DEVNULL)
subprocess.run(['xcrun', 'simctl', 'uninstall', dev, 'com.nolifa.app'], stderr=subprocess.DEVNULL)  # a fresh start, so the sign-in shows
raw = out.replace('.mp4', '.mov')
rec = subprocess.Popen(['xcrun', 'simctl', 'io', dev, 'recordVideo', '--codec', 'h264', '--force', raw], stderr=subprocess.DEVNULL)
t0 = time.time(); begin = None
p = subprocess.Popen(['flutter', 'test', 'integration_test/demo_test.dart', '-d', dev, '--flavor', 'nolifa', '--dart-define=QA_SCENE=' + scene, '--dart-define=QUIET_PERMISSIONS=true'],
                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
import threading
last = [time.time()]
def watchdog():
    while p.poll() is None:
        time.sleep(5)
        if time.time() - last[0] > 100:
            print('DEMO watchdog: stopped, no progress for 100 s'); p.kill(); return
threading.Thread(target=watchdog, daemon=True).start()
for line in p.stdout:
    last[0] = time.time()
    if 'DEMO begin' in line and begin is None:
        begin = time.time() - t0
        subprocess.run(['xcrun', 'simctl', 'privacy', dev, 'grant', 'location', 'com.nolifa.app'], stderr=subprocess.DEVNULL)
    if "DEMO" in line or 'All tests passed' in line or 'Some tests failed' in line or 'Expected' in line: print(line.rstrip())
p.wait()
time.sleep(1)
rec.send_signal(signal.SIGINT); rec.wait()
ss = max(0, (begin or 0) - 0.5)
subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-ss', str(ss), '-i', raw, '-vf', 'scale=-2:1280', '-r', '30', '-pix_fmt', 'yuv420p', '-an', out], check=True)
print('saved', out, 'trimmed', round(ss, 1), 's')
