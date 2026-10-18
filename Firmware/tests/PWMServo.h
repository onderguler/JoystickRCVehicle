#pragma once
#include <cstdint>
#include <cstdlib>
#include <algorithm>
#include <deque>
using std::min; using std::max;
#define OUTPUT 1
#define HIGH 1
#define LOW 0
extern unsigned long fakeTime;
extern int pins[256];
inline unsigned long millis(){ return fakeTime; }
inline void pinMode(int,int){}
inline void analogWrite(int p,int v){pins[p]=v;}
inline void digitalWrite(int p,int v){pins[p]=v;}
inline void delayMicroseconds(unsigned int){}
inline long map(long x,long a,long b,long c,long d){return (x-a)*(d-c)/(b-a)+c;}
inline int constrain(int x,int a,int b){return std::max(a,std::min(x,b));}
struct FakeSerial {
  std::deque<uint8_t> data;
  void (*beforeRead)() = nullptr;
  void begin(int) {}
  int available() { return data.size(); }
  int read() {
    if (beforeRead) beforeRead();
    if (data.empty()) return -1;
    int value = data.front();
    data.pop_front();
    return value;
  }
};
extern FakeSerial Serial;
struct PWMServo{int angle=0;void attach(int){} void write(int x){angle=x;}};
void stopUnsafeOutputs();
void readCommandBytes();
void applyLatestCommand();
void enforceCommandWatchdog();
void enforceCommandWatchdogAt(unsigned long);
void updateMotorOutputs();
void updateServoOutputs();
void ingestCommandByte(uint8_t);
bool processCommandPacket(const uint8_t*);
void resynchronizeInputBuffer();
bool isNewerSequence(uint8_t);
int16_t decodeSignedInt16(uint8_t,uint8_t);
uint8_t crc8(const uint8_t*,uint8_t);
void setMotorCommands(int,int);
void setTurretTarget(int,int);
void setDeviceFlags(uint8_t);
int commandToPWM(int);
int nextRampedPWM(int,int);
void setMotorSpeed(uint8_t,int,uint8_t,uint8_t);
int stepToward(int,int,int);
