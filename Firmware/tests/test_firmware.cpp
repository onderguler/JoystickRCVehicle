// Host-only regression tests: execute the production sketch with inert pin/serial shims.
#include <array>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>
#include "PWMServo.h"

unsigned long fakeTime = 0;
int pins[256] = {};
FakeSerial Serial;
#ifndef FIRMWARE_PATH
#define FIRMWARE_PATH "../fastBluetooth/fastBluetooth.ino"
#endif
#include FIRMWARE_PATH

using Packet = std::array<uint8_t, 10>;
#define CHECK(condition) do { if (!(condition)) throw std::runtime_error(#condition); } while (false)

Packet packet(uint8_t sequence, int left = 0, int right = 0,
              int x = 0, int y = 0, uint8_t flags = 0) {
  const auto ux = static_cast<uint16_t>(x);
  const auto uy = static_cast<uint16_t>(y);
  Packet p = {0xA2, sequence, static_cast<uint8_t>(left), static_cast<uint8_t>(right),
              static_cast<uint8_t>(ux), static_cast<uint8_t>(ux >> 8),
              static_cast<uint8_t>(uy), static_cast<uint8_t>(uy >> 8), flags, 0};
  p[9] = crc8(p.data(), 9);
  return p;
}

void feed(const Packet& p, size_t first = 0, size_t end = 10) {
  for (size_t i = first; i < end; ++i) Serial.data.push_back(p[i]);
}

void reset() {
  fakeTime = 0;
  Serial.data.clear();
  Serial.beforeRead = nullptr;
  std::fill(std::begin(pins), std::end(pins), 0);
  inputLength = 0;
  hasAcceptedSequence = false;
  commandIsActive = false;
  lastAcceptedSequence = 0;
  lastValidCommandAt = 0;
  hasPendingCommand = false;
  lastMotorRampAt = 0;
  lastServoUpdateAt = 0;
  currentHorizontalAngle = currentVerticalAngle = 90;
  stopUnsafeOutputs();
}

void checkSafe() {
  CHECK(currentLeftPWM == 0 && currentRightPWM == 0);
  CHECK(targetLeftPWM == 0 && targetRightPWM == 0);
  CHECK(pins[MOTOR_ENABLE_A] == 0 && pins[MOTOR_ENABLE_B] == 0);
  CHECK(pins[LASER] == LOW && pins[FIRLATICILAR] == LOW && pins[ATESLEYICI] == LOW);
}

void watchdogDropsPartialFrame() {
  feed(packet(116)); loop();
  fakeTime = 25;
  feed(packet(117, 99, 99, 0, 0, FLAG_LASER), 0, 9); loop();
  CHECK(inputLength == 9);
  fakeTime = 250; loop();
  CHECK(!commandIsActive);
  CHECK(inputLength == 0);
  checkSafe();
}

void delayedTailCannotReviveCommand() {
  feed(packet(0)); loop();
  const auto stale = packet(1, 99, 99, 0, 0, VALID_FLAGS);
  fakeTime = 25; feed(stale, 0, 9); loop();
  fakeTime = 250; loop();
  fakeTime = 5000; feed(stale, 9); loop();
  CHECK(!commandIsActive);
  checkSafe();
}

void neutralHeaderCannotCompleteStaleCRC() {
  feed(packet(116)); loop();
  const auto stale = packet(117, 99, 99, 0, 0, FLAG_LASER);
  CHECK(stale[9] == COMMAND_HEADER);
  fakeTime = 25; feed(stale, 0, 9); loop();
  fakeTime = 250; loop();
  fakeTime = 5000; feed(packet(0)); loop();
  CHECK(lastAcceptedSequence == 0);
  for (fakeTime = 5001; fakeTime <= 5250; ++fakeTime) {
    if (fakeTime % 25 == 0) feed(packet(static_cast<uint8_t>((fakeTime - 5000) / 25)));
    loop(); checkSafe();
  }
  CHECK(lastAcceptedSequence == 10);
}

void startupPartialFrameExpiresBeforeNextByte() {
  const auto stale = packet(117, 99, 99, 0, 0, FLAG_LASER);
  feed(stale, 0, 9); loop();
  CHECK(!commandIsActive);
  fakeTime = 5000; feed(packet(0)); loop();
  CHECK(lastAcceptedSequence == 0);
  checkSafe();
}

void neutralAtWatchdogBoundaryCannotReviveCommand() {
  feed(packet(116)); loop();
  fakeTime = 25;
  feed(packet(117, 99, 99, 0, 0, FLAG_LASER), 0, 9); loop();
  for (fakeTime = 26; fakeTime < 250; ++fakeTime) loop();
  // The fragment is only 225 ms old, but its accepted session is 250 ms old.
  feed(packet(0)); loop();
  CHECK(lastAcceptedSequence == 0);
  for (fakeTime = 251; fakeTime <= 500; ++fakeTime) {
    if (fakeTime % 25 == 0) feed(packet(static_cast<uint8_t>((fakeTime - 250) / 25)));
    loop(); checkSafe();
  }
  CHECK(lastAcceptedSequence == 10);
}

void watchdogDeadlineDuringSerialReadCannotReviveCommand() {
  feed(packet(116)); loop();
  fakeTime = 25;
  feed(packet(117, 99, 99, 0, 0, FLAG_LASER), 0, 9); loop();
  fakeTime = 249;
  feed(packet(0));
  Serial.beforeRead = [] {
    fakeTime = 250;
    Serial.beforeRead = nullptr;
  };
  loop();
  CHECK(lastAcceptedSequence == 0);
  checkSafe();
}

void inactivePartialFrameExpires() {
  feed(packet(116)); loop();
  fakeTime = 250; loop();
  fakeTime = 300; feed(packet(117, 99, 99, 0, 0, FLAG_LASER), 0, 9); loop();
  CHECK(!commandIsActive);
  fakeTime = 1000; feed(packet(0)); loop();
  CHECK(lastAcceptedSequence == 0);
  checkSafe();
}

void timeoutCheckedBeforeParsingWhenLoopWasDelayed() {
  feed(packet(116)); loop();
  fakeTime = 25; feed(packet(117, 99, 99, 0, 0, FLAG_LASER), 0, 9); loop();
  // No intervening watchdog loop. The parser itself must expire the fragment.
  fakeTime = 5000; feed(packet(118)); loop();
  CHECK(lastAcceptedSequence == 118);
  checkSafe();
}

void partialFrameTimeoutBoundary() {
  auto p = packet(1, 99, 99, 0, 0, FLAG_LASER);
  feed(p, 0, 9); loop();
  fakeTime = 249; feed(p, 9); loop();
  CHECK(commandIsActive && lastAcceptedSequence == 1);
  reset();
  feed(p, 0, 9); loop();
  fakeTime = 250; feed(p, 9); loop();
  CHECK(!commandIsActive);
  checkSafe();
}

void fragmentedPacketWithinTimeoutAccepted() {
  const auto p = packet(42, 99, -99, 254, -254, VALID_FLAGS);
  for (size_t i = 0; i < p.size(); ++i) {
    fakeTime = static_cast<unsigned long>(i * 2);
    feed(p, i, i + 1); loop();
  }
  CHECK(commandIsActive && lastAcceptedSequence == 42);
  CHECK(targetLeftPWM == 255 && targetRightPWM == 255);
  CHECK(pins[LASER] == HIGH && pins[FIRLATICILAR] == HIGH && pins[ATESLEYICI] == HIGH);
}

void unsignedTimeRolloverExpiresPartial() {
  fakeTime = std::numeric_limits<unsigned long>::max() - 100;
  feed(packet(117, 99, 99, 0, 0, FLAG_LASER), 0, 9); loop();
  fakeTime = 149; feed(packet(0)); loop(); // Exactly 250 ms across wrap.
  CHECK(lastAcceptedSequence == 0);
  checkSafe();
}

void invalidPacketsAreAtomic() {
  const auto initial = packet(10, 25, -35, 20, -40, FLAG_LASER);
  feed(initial); loop();
  const auto originalTarget = targetLeftPWM;
  std::vector<Packet> invalid = {
    packet(11, 100), packet(11, 0, -100), packet(11, 0, 0, 255),
    packet(11, 0, 0, 0, -255), packet(11, 0, 0, 0, 0, 8)
  };
  auto badCRC = packet(11); badCRC[9] ^= 1; invalid.push_back(badCRC);
  for (const auto& p : invalid) {
    CHECK(!processCommandPacket(p.data()));
    CHECK(lastAcceptedSequence == 10 && targetLeftPWM == originalTarget);
    CHECK(!hasPendingCommand);
    CHECK(pins[LASER] == HIGH);
  }
}

void sequenceWrapRejectsDuplicatesAndOldFrames() {
  feed(packet(255, 25)); loop();
  fakeTime = 10; feed(packet(0, 35)); loop();
  CHECK(lastAcceptedSequence == 0);
  CHECK(targetLeftPWM == commandToPWM(35));
  fakeTime = 20;
  feed(packet(0, 99)); feed(packet(255, 99)); feed(packet(128, 99)); loop();
  CHECK(lastAcceptedSequence == 0 && lastValidCommandAt == 10);
  CHECK(targetLeftPWM == commandToPWM(35));
}

void latestValidPacketWinsAndParserResynchronizes() {
  auto corrupted = packet(1); corrupted[9] ^= 1;
  feed(corrupted); feed(packet(2, 99, 99)); feed(packet(3)); loop();
  CHECK(lastAcceptedSequence == 3); checkSafe();
  // A valid packet starts inside the prior malformed ten-byte window.
  reset();
  Serial.data = {COMMAND_HEADER, 0xEE, 0xEE};
  feed(packet(4)); loop();
  CHECK(lastAcceptedSequence == 4); checkSafe();
}

void watchdogStopsAllUnsafeOutputsAtBoundary() {
  feed(packet(42, 99, 99, 100, -100, VALID_FLAGS)); loop();
  fakeTime = 10; loop();
  CHECK(currentLeftPWM != 0 && pins[LASER] == HIGH);
  fakeTime = 249; loop(); CHECK(commandIsActive);
  fakeTime = 250; loop(); CHECK(!commandIsActive);
  CHECK(!hasAcceptedSequence && !hasPendingCommand);
  checkSafe();
  CHECK(targetHorizontalAngle == currentHorizontalAngle);
  CHECK(targetVerticalAngle == currentVerticalAngle);
}

void crcVectorsAndMotorRampProperties() {
  const Packet vector = {0xA2, 0x7F, 0x9D, 0x9D, 0x02, 0xFF, 0x02, 0xFF, 0x07, 0x07};
  CHECK(crc8(vector.data(), 9) == 0x07);
  const uint8_t standard[] = {'1','2','3','4','5','6','7','8','9'};
  CHECK(crc8(standard, 9) == 0xF4);
  for (int a = -99; a <= 99; ++a) for (int b = -99; b <= 99; ++b) {
    int current = commandToPWM(a), target = commandToPWM(b);
    for (int n = 0; n < 100; ++n) {
      const int next = nextRampedPWM(current, target);
      CHECK(abs(next) <= 255);
      CHECK(!current || !next || ((current > 0) == (next > 0)));
      current = next;
    }
    CHECK(current == target);
  }
}

int main() {
  setup();
  const std::vector<std::pair<const char*, void (*)()>> tests = {
    {"watchdog drops partial frame", watchdogDropsPartialFrame},
    {"delayed tail cannot revive command", delayedTailCannotReviveCommand},
    {"neutral header cannot complete stale CRC", neutralHeaderCannotCompleteStaleCRC},
    {"neutral at watchdog deadline cannot revive command", neutralAtWatchdogBoundaryCannotReviveCommand},
    {"watchdog deadline during serial read", watchdogDeadlineDuringSerialReadCannotReviveCommand},
    {"startup partial frame expires", startupPartialFrameExpiresBeforeNextByte},
    {"inactive partial frame expires", inactivePartialFrameExpires},
    {"timeout checked before parsing", timeoutCheckedBeforeParsingWhenLoopWasDelayed},
    {"partial frame timeout boundary", partialFrameTimeoutBoundary},
    {"valid fragmentation accepted", fragmentedPacketWithinTimeoutAccepted},
    {"unsigned millis rollover", unsignedTimeRolloverExpiresPartial},
    {"invalid packets rejected atomically", invalidPacketsAreAtomic},
    {"sequence wrap and duplicate rejection", sequenceWrapRejectsDuplicatesAndOldFrames},
    {"latest wins and resynchronization", latestValidPacketWinsAndParserResynchronizes},
    {"watchdog output boundary", watchdogStopsAllUnsafeOutputsAtBoundary},
    {"CRC vectors and 39601 motor transitions", crcVectorsAndMotorRampProperties}
  };
  size_t failures = 0;
  for (const auto& test : tests) {
    reset();
    try { test.second(); std::cout << "PASS: " << test.first << '\n'; }
    catch (const std::exception& error) {
      ++failures; std::cout << "FAIL: " << test.first << ": " << error.what() << '\n';
    }
  }
  std::cout << (tests.size() - failures) << '/' << tests.size() << " host firmware tests passed\n";
  return failures ? 1 : 0;
}
