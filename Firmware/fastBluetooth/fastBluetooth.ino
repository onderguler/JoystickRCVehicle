#include <PWMServo.h>

// Original vehicle wiring.
const uint8_t MOTOR_IN1 = 8;
const uint8_t MOTOR_IN2 = 6;
const uint8_t MOTOR_IN3 = 7;
const uint8_t MOTOR_IN4 = 12;
const uint8_t MOTOR_ENABLE_A = 3;
const uint8_t MOTOR_ENABLE_B = 5;

const uint8_t SERVO_HORIZONTAL = 10;
const uint8_t SERVO_VERTICAL = 9;

const uint8_t LASER = 2;
const uint8_t FIRLATICILAR = 11;
const uint8_t ATESLEYICI = 4;

const unsigned long COMMAND_TIMEOUT_MS = 250;
const int MOTOR_COMMAND_MIN = -99;
const int MOTOR_COMMAND_MAX = 99;
const int MOTOR_COMMAND_DEADZONE = 20;
const int MOTOR_MINIMUM_PWM = 70;
const unsigned int MOTOR_DIRECTION_DEADTIME_US = 100;
const unsigned long MOTOR_RAMP_INTERVAL_MS = 10;
const int MOTOR_ACCELERATION_STEP = 6;
const int MOTOR_DECELERATION_STEP = 12;
const int TURRET_COMMAND_MIN = -254;
const int TURRET_COMMAND_MAX = 254;
const int HORIZONTAL_ANGLE_MIN = 10;
const int HORIZONTAL_ANGLE_MAX = 180;
const int VERTICAL_ANGLE_MIN = 52;
const int VERTICAL_ANGLE_MAX = 108;
const unsigned long SERVO_UPDATE_INTERVAL_MS = 5;
const int SERVO_STEP_DEGREES = 1;

const uint8_t FLAG_LASER = 1 << 0;
const uint8_t FLAG_FIRE = 1 << 1;
const uint8_t FLAG_TRIGGER = 1 << 2;
const uint8_t VALID_FLAGS = FLAG_LASER | FLAG_FIRE | FLAG_TRIGGER;

const uint8_t COMMAND_HEADER = 0xA2;
const uint8_t COMMAND_PACKET_SIZE = 10;
const uint8_t COMMAND_CRC_INDEX = COMMAND_PACKET_SIZE - 1;
const uint8_t CRC8_POLYNOMIAL = 0x07;

PWMServo horizontalServo;
PWMServo verticalServo;

int targetHorizontalAngle = 90;
int targetVerticalAngle = 90;
int currentHorizontalAngle = 90;
int currentVerticalAngle = 90;

int targetLeftPWM = 0;
int targetRightPWM = 0;
int currentLeftPWM = 0;
int currentRightPWM = 0;
unsigned long lastMotorRampAt = 0;
unsigned long lastServoUpdateAt = 0;

uint8_t inputBuffer[COMMAND_PACKET_SIZE];
uint8_t inputLength = 0;
bool commandIsActive = false;
bool hasAcceptedSequence = false;
uint8_t lastAcceptedSequence = 0;
unsigned long lastValidCommandAt = 0;

bool hasPendingCommand = false;
int pendingLeftMotor = 0;
int pendingRightMotor = 0;
int pendingTurretX = 0;
int pendingTurretY = 0;
uint8_t pendingFlags = 0;

void setup() {
  Serial.begin(9600);

  horizontalServo.attach(SERVO_HORIZONTAL);
  verticalServo.attach(SERVO_VERTICAL);
  horizontalServo.write(targetHorizontalAngle);
  verticalServo.write(targetVerticalAngle);

  pinMode(MOTOR_IN1, OUTPUT);
  pinMode(MOTOR_IN2, OUTPUT);
  pinMode(MOTOR_IN3, OUTPUT);
  pinMode(MOTOR_IN4, OUTPUT);
  pinMode(MOTOR_ENABLE_A, OUTPUT);
  pinMode(MOTOR_ENABLE_B, OUTPUT);

  pinMode(LASER, OUTPUT);
  pinMode(FIRLATICILAR, OUTPUT);
  pinMode(ATESLEYICI, OUTPUT);

  stopUnsafeOutputs();
}

void loop() {
  readCommandBytes();
  applyLatestCommand();
  enforceCommandWatchdog();
  updateMotorOutputs();
  updateServoOutputs();
}

void readCommandBytes() {
  while (Serial.available() > 0) {
    const int incoming = Serial.read();
    if (incoming >= 0) {
      ingestCommandByte((uint8_t)incoming);
    }
  }
}

void ingestCommandByte(uint8_t incoming) {
  if (inputLength == 0) {
    if (incoming == COMMAND_HEADER) {
      inputBuffer[inputLength++] = incoming;
    }
    return;
  }

  inputBuffer[inputLength++] = incoming;
  if (inputLength < COMMAND_PACKET_SIZE) {
    return;
  }

  if (processCommandPacket(inputBuffer)) {
    inputLength = 0;
  } else {
    resynchronizeInputBuffer();
  }
}

bool processCommandPacket(const uint8_t* packet) {
  if (packet[0] != COMMAND_HEADER ||
      crc8(packet, COMMAND_CRC_INDEX) != packet[COMMAND_CRC_INDEX]) {
    return false;
  }

  const uint8_t sequence = packet[1];
  const int leftMotor = (int8_t)packet[2];
  const int rightMotor = (int8_t)packet[3];
  const int turretX = decodeSignedInt16(packet[4], packet[5]);
  const int turretY = decodeSignedInt16(packet[6], packet[7]);
  const uint8_t flags = packet[8];

  if (leftMotor < MOTOR_COMMAND_MIN || leftMotor > MOTOR_COMMAND_MAX ||
      rightMotor < MOTOR_COMMAND_MIN || rightMotor > MOTOR_COMMAND_MAX ||
      turretX < TURRET_COMMAND_MIN || turretX > TURRET_COMMAND_MAX ||
      turretY < TURRET_COMMAND_MIN || turretY > TURRET_COMMAND_MAX ||
      flags > VALID_FLAGS) {
    return false;
  }

  if (!isNewerSequence(sequence)) {
    return true;
  }

  pendingLeftMotor = leftMotor;
  pendingRightMotor = rightMotor;
  pendingTurretX = turretX;
  pendingTurretY = turretY;
  pendingFlags = flags;
  hasPendingCommand = true;

  lastAcceptedSequence = sequence;
  hasAcceptedSequence = true;
  lastValidCommandAt = millis();
  commandIsActive = true;
  return true;
}

void applyLatestCommand() {
  if (!hasPendingCommand) {
    return;
  }

  setMotorCommands(pendingLeftMotor, pendingRightMotor);
  setTurretTarget(pendingTurretX, pendingTurretY);
  setDeviceFlags(pendingFlags);
  hasPendingCommand = false;
}

void resynchronizeInputBuffer() {
  uint8_t nextHeaderIndex = COMMAND_PACKET_SIZE;
  for (uint8_t index = 1; index < COMMAND_PACKET_SIZE; index++) {
    if (inputBuffer[index] == COMMAND_HEADER) {
      nextHeaderIndex = index;
      break;
    }
  }

  if (nextHeaderIndex == COMMAND_PACKET_SIZE) {
    inputLength = 0;
    return;
  }

  inputLength = COMMAND_PACKET_SIZE - nextHeaderIndex;
  for (uint8_t index = 0; index < inputLength; index++) {
    inputBuffer[index] = inputBuffer[nextHeaderIndex + index];
  }
}

bool isNewerSequence(uint8_t sequence) {
  if (!hasAcceptedSequence) {
    return true;
  }

  const uint8_t distance = sequence - lastAcceptedSequence;
  return distance > 0 && distance < 128;
}

int16_t decodeSignedInt16(uint8_t lowByte, uint8_t highByte) {
  const uint16_t rawValue = (uint16_t)lowByte | ((uint16_t)highByte << 8);
  return (int16_t)rawValue;
}

uint8_t crc8(const uint8_t* data, uint8_t length) {
  uint8_t crc = 0;
  for (uint8_t index = 0; index < length; index++) {
    crc ^= data[index];
    for (uint8_t bit = 0; bit < 8; bit++) {
      if ((crc & 0x80) != 0) {
        crc = (uint8_t)((crc << 1) ^ CRC8_POLYNOMIAL);
      } else {
        crc <<= 1;
      }
    }
  }
  return crc;
}

void setMotorCommands(int leftCommand, int rightCommand) {
  targetLeftPWM = commandToPWM(leftCommand);
  targetRightPWM = -commandToPWM(rightCommand);
}

int commandToPWM(int command) {
  const int magnitude = abs(command);
  if (magnitude < MOTOR_COMMAND_DEADZONE) {
    return 0;
  }

  const int pwm = (int)map(
    magnitude,
    MOTOR_COMMAND_DEADZONE,
    MOTOR_COMMAND_MAX,
    MOTOR_MINIMUM_PWM,
    255
  );
  return command < 0 ? -pwm : pwm;
}

void updateMotorOutputs() {
  const unsigned long now = millis();
  if (now - lastMotorRampAt < MOTOR_RAMP_INTERVAL_MS) {
    return;
  }
  lastMotorRampAt = now;

  const int nextLeftPWM = nextRampedPWM(currentLeftPWM, targetLeftPWM);
  const int nextRightPWM = nextRampedPWM(currentRightPWM, targetRightPWM);

  if (nextLeftPWM != currentLeftPWM) {
    currentLeftPWM = nextLeftPWM;
    setMotorSpeed(MOTOR_ENABLE_B, currentLeftPWM, MOTOR_IN3, MOTOR_IN4);
  }
  if (nextRightPWM != currentRightPWM) {
    currentRightPWM = nextRightPWM;
    setMotorSpeed(MOTOR_ENABLE_A, currentRightPWM, MOTOR_IN1, MOTOR_IN2);
  }
}

int nextRampedPWM(int currentPWM, int targetPWM) {
  if (currentPWM == targetPWM) {
    return currentPWM;
  }

  if (currentPWM == 0) {
    if (targetPWM == 0) {
      return 0;
    }
    return targetPWM > 0 ? MOTOR_MINIMUM_PWM : -MOTOR_MINIMUM_PWM;
  }

  const bool directionChanged = (currentPWM > 0) != (targetPWM > 0);
  if (targetPWM == 0 || directionChanged) {
    const int nextMagnitude = abs(currentPWM) - MOTOR_DECELERATION_STEP;
    if (nextMagnitude < MOTOR_MINIMUM_PWM) {
      return 0;
    }
    return currentPWM > 0 ? nextMagnitude : -nextMagnitude;
  }

  const int currentMagnitude = abs(currentPWM);
  const int targetMagnitude = abs(targetPWM);
  const int step = targetMagnitude > currentMagnitude
    ? MOTOR_ACCELERATION_STEP
    : MOTOR_DECELERATION_STEP;
  const int nextMagnitude = targetMagnitude > currentMagnitude
    ? min(currentMagnitude + step, targetMagnitude)
    : max(currentMagnitude - step, targetMagnitude);
  return targetPWM > 0 ? nextMagnitude : -nextMagnitude;
}

void setMotorSpeed(
  uint8_t enablePin,
  int speed,
  uint8_t firstDirectionPin,
  uint8_t secondDirectionPin
) {
  speed = constrain(speed, -255, 255);
  analogWrite(enablePin, 0);

  if (speed == 0) {
    digitalWrite(firstDirectionPin, LOW);
    digitalWrite(secondDirectionPin, LOW);
  } else if (speed > 0) {
    delayMicroseconds(MOTOR_DIRECTION_DEADTIME_US);
    digitalWrite(firstDirectionPin, LOW);
    digitalWrite(secondDirectionPin, HIGH);
    analogWrite(enablePin, speed);
  } else {
    delayMicroseconds(MOTOR_DIRECTION_DEADTIME_US);
    digitalWrite(firstDirectionPin, HIGH);
    digitalWrite(secondDirectionPin, LOW);
    analogWrite(enablePin, -speed);
  }
}

void setTurretTarget(int horizontalCommand, int verticalCommand) {
  targetHorizontalAngle = (int)map(
    horizontalCommand,
    TURRET_COMMAND_MIN,
    TURRET_COMMAND_MAX,
    HORIZONTAL_ANGLE_MIN,
    HORIZONTAL_ANGLE_MAX
  );
  targetVerticalAngle = (int)map(
    verticalCommand,
    TURRET_COMMAND_MIN,
    TURRET_COMMAND_MAX,
    VERTICAL_ANGLE_MIN,
    VERTICAL_ANGLE_MAX
  );

}

void updateServoOutputs() {
  const unsigned long now = millis();
  if (now - lastServoUpdateAt < SERVO_UPDATE_INTERVAL_MS) {
    return;
  }
  lastServoUpdateAt = now;

  const int nextHorizontalAngle = stepToward(
    currentHorizontalAngle,
    targetHorizontalAngle,
    SERVO_STEP_DEGREES
  );
  const int nextVerticalAngle = stepToward(
    currentVerticalAngle,
    targetVerticalAngle,
    SERVO_STEP_DEGREES
  );

  if (nextHorizontalAngle != currentHorizontalAngle) {
    currentHorizontalAngle = nextHorizontalAngle;
    horizontalServo.write(currentHorizontalAngle);
  }
  if (nextVerticalAngle != currentVerticalAngle) {
    currentVerticalAngle = nextVerticalAngle;
    verticalServo.write(currentVerticalAngle);
  }
}

int stepToward(int currentValue, int targetValue, int maximumStep) {
  if (currentValue < targetValue) {
    return min(currentValue + maximumStep, targetValue);
  }
  if (currentValue > targetValue) {
    return max(currentValue - maximumStep, targetValue);
  }
  return currentValue;
}

void setDeviceFlags(uint8_t flags) {
  const bool fireEnabled = (flags & FLAG_FIRE) != 0;
  const bool triggerEnabled = fireEnabled && (flags & FLAG_TRIGGER) != 0;

  digitalWrite(LASER, (flags & FLAG_LASER) != 0 ? HIGH : LOW);
  digitalWrite(FIRLATICILAR, fireEnabled ? HIGH : LOW);
  digitalWrite(ATESLEYICI, triggerEnabled ? HIGH : LOW);
}

void enforceCommandWatchdog() {
  if (commandIsActive && millis() - lastValidCommandAt >= COMMAND_TIMEOUT_MS) {
    stopUnsafeOutputs();
    commandIsActive = false;
    hasAcceptedSequence = false;
  }
}

void stopUnsafeOutputs() {
  hasPendingCommand = false;
  targetLeftPWM = 0;
  targetRightPWM = 0;
  currentLeftPWM = 0;
  currentRightPWM = 0;
  targetHorizontalAngle = currentHorizontalAngle;
  targetVerticalAngle = currentVerticalAngle;

  analogWrite(MOTOR_ENABLE_A, 0);
  analogWrite(MOTOR_ENABLE_B, 0);
  digitalWrite(MOTOR_IN1, LOW);
  digitalWrite(MOTOR_IN2, LOW);
  digitalWrite(MOTOR_IN3, LOW);
  digitalWrite(MOTOR_IN4, LOW);
  digitalWrite(LASER, LOW);
  digitalWrite(FIRLATICILAR, LOW);
  digitalWrite(ATESLEYICI, LOW);
}
