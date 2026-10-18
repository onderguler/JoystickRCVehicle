# Firmware host regression tests

Run from the repository root:

```sh
./Firmware/tests/run_host_tests.sh
```

The script compiles the **production** `fastBluetooth.ino` directly with `g++`,
AddressSanitizer and UndefinedBehaviorSanitizer, using a minimal inert Arduino
and PWMServo shim. No serial device, Bluetooth adapter, motor or other hardware
is accessed. It needs Bash and a C++17 compiler; override `CXX` if required.
Leak detection defaults off because LeakSanitizer cannot enumerate processes in
some sandboxed CI environments. Set `ASAN_OPTIONS=detect_leaks=1` in an environment
that supports it.

The 16 tests cover:

- Watchdog clearing an incomplete frame and rejecting a delayed final byte
- The exact old CRC=`0xA2` / new neutral-header reconnect regression
- Partial frames at startup and while inactive
- Timeout before ingest after a delayed main loop, the 249/250 ms boundary,
  valid fragmentation, and unsigned `millis()` rollover
- Atomic CRC/range rejection, sequence wrap, duplicates and old commands
- Latest-wins parsing, corrupt-stream resynchronization, and watchdog outputs
- Two CRC vectors and all 39,601 legal motor-command transition pairs

For a baseline comparison against an unchanged sketch:

```sh
git show f96419beb993fc2f67f8423e8534777069eda56f:Firmware/fastBluetooth/fastBluetooth.ino > /tmp/fastBluetooth-before.ino
./Firmware/tests/run_host_tests.sh --firmware /tmp/fastBluetooth-before.ino
```

The baseline is expected to fail ten regression cases. A successful run of
the fixed sketch is **not** an AVR compile, an electrical timing test, or a
physical vehicle safety certification. The host's `unsigned long` width may
also differ from AVR; the wrap test exercises the unsigned subtraction rule
at the host width, not the AVR ABI.

Before deployment, also compile with the Arduino AVR toolchain and test on the
bench with drive/auxiliary actuators disconnected. Keep the receiver watchdog;
BLE/UDP send completion is not a vehicle-level acknowledgement.
