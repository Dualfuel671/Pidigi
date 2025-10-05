// AX.25 / APRS 1200 baud AFSK transmit scaffolding for ESP32-WROOM-32U -> Baofeng
// This is an initial stub. It builds a test frame and generates AFSK tones.
// Next steps: verify audio level, implement full AX.25 framing (CRC, bit stuffing),
// optionally replace manual AFSK with RadioLib helper once stable.

#include <Arduino.h>
#include <RadioLib.h>

// ---------------- Configuration ----------------
// YOUR CALL SIGN (up to 6 chars) and SSID (0-15)
static const char CALL[] = "N0CALL"; // TODO: change to your call
static const uint8_t CALL_SSID = 9;   // e.g. -9 for mobile

// Destination / path (APRS typical)
static const char DEST[] = "APESP"; // custom destination
static const uint8_t DEST_SSID = 0;

// Digipeater path example (WIDE1-1,WIDE2-1). For now we keep an empty path.
// Later implement path fields.

// PTT and Audio settings
// PTT will drive an NPN transistor to ground Baofeng MIC/PTT line.
constexpr int PIN_PTT = 15;      // choose a free GPIO, ensure not strapping pin
constexpr int PIN_AUDIO = 25;    // DAC1 (GPIO25) for analog output to mic (through RC network)

// AFSK parameters (Bell 202): Mark 1200 Hz, Space 2200 Hz, 1200 baud
constexpr float AFSK_MARK = 1200.0f;
constexpr float AFSK_SPACE = 2200.0f;
constexpr uint16_t BAUD = 1200;

// Sample rate for DAC generation. 9600 gives 8 samples per bit at 1200 baud.
constexpr uint16_t SAMPLE_RATE = 9600;
// Timer interval in microseconds
constexpr uint32_t SAMPLE_INTERVAL_US = 1000000UL / SAMPLE_RATE;

// Beacon interval (ms)
constexpr uint32_t BEACON_INTERVAL_MS = 60UL * 1000UL; // 60s for testing

// ---------------- State ----------------
hw_timer_t* afskTimer = nullptr;
volatile bool transmitting = false;
volatile uint32_t sampleIndex = 0;

// Simple bit queue (very small for scaffolding)
constexpr size_t MAX_BITS = 2048;
volatile uint8_t bitBuf[MAX_BITS/8];
volatile size_t totalBits = 0;
volatile size_t bitPos = 0; // current bit being sent

// Tone generation state
volatile float currentFreq = AFSK_MARK;
volatile float phase = 0.0f;

// Forward decl
void startTransmit();
void stopTransmit();
void enqueueTestFrame();

// Utility: set/clear bit
static inline void setBit(volatile uint8_t* buf, size_t idx, bool v) {
  size_t byte = idx >> 3;
  uint8_t mask = 1 << (idx & 7);
  if(v) buf[byte] |= mask; else buf[byte] &= ~mask;
}

static inline bool getBit(volatile uint8_t* buf, size_t idx) {
  size_t byte = idx >> 3;
  return (buf[byte] >> (idx & 7)) & 0x1;
}

// Simple CRC-16-IBM (reflected) used by AX.25 (to be verified) - placeholder
uint16_t ax25_crc(const uint8_t* data, size_t len) {
  uint16_t crc = 0xFFFF;
  for(size_t i=0;i<len;i++) {
    uint8_t b = data[i];
    for(uint8_t j=0;j<8;j++) {
      bool mix = (crc ^ b) & 0x01;
      crc >>= 1;
      if(mix) crc ^= 0x8408; // poly reversed 0x1021
      b >>= 1;
    }
  }
  return ~crc; // output inverted
}

// ISR: Generate next audio sample based on current bit timing
void IRAM_ATTR onSampleTimer() {
  if(!transmitting) return;
  // Determine which bit we are in (8 samples per bit with 9600/1200)
  const uint16_t SAMPLES_PER_BIT = SAMPLE_RATE / BAUD; // 8
  size_t currentBit = sampleIndex / SAMPLES_PER_BIT;
  if(currentBit >= totalBits) {
    // finished
    stopTransmit();
    return;
  }
  bool bit = getBit(bitBuf, currentBit);
  // NRZI (simplified): in AX.25, a '0' causes transition, '1' no transition.
  // Implement basic NRZI by toggling frequency on 0.
  static bool lastBit = true;
  if(bit == false) {
    // toggle between MARK and SPACE
    currentFreq = (currentFreq == AFSK_MARK) ? AFSK_SPACE : AFSK_MARK;
  }
  lastBit = bit;

  // Generate sine sample at currentFreq
  float increment = (2.0f * PI * currentFreq) / SAMPLE_RATE;
  phase += increment;
  if(phase > 2.0f * PI) phase -= 2.0f * PI;
  float s = (sinf(phase) * 0.45f + 0.5f); // 0..1
  uint8_t value = (uint8_t)(s * 255);
  dacWrite(PIN_AUDIO, value);

  sampleIndex++;
}

void startTransmit() {
  if(transmitting) return;
  bitPos = 0;
  sampleIndex = 0;
  phase = 0;
  currentFreq = AFSK_MARK;
  transmitting = true;
  digitalWrite(PIN_PTT, HIGH); // key
}

void stopTransmit() {
  transmitting = false;
  digitalWrite(PIN_PTT, LOW); // unkey
}

// Build a minimal AX.25 UI frame bits (very incomplete; for demonstration only)
void enqueueTestFrame() {
  memset((void*)bitBuf, 0, sizeof(bitBuf));
  totalBits = 0;

  // Add flag 0x7E repeated 16 times preamble
  for(int i=0;i<16;i++) {
    uint8_t flag = 0x7E;
    for(int b=0;b<8;b++) {
      bool bit = (flag >> b) & 0x1; // LSB first per AX.25 bit order
      setBit(bitBuf, totalBits++, bit);
    }
  }

  // Placeholder payload ASCII
  const char *payload = "Hello AX25";
  size_t len = strlen(payload);
  // Directly push payload bytes (LSB first) - missing header & addresses
  for(size_t i=0;i<len;i++) {
    uint8_t c = payload[i];
    for(int b=0;b<8;b++) {
      setBit(bitBuf, totalBits++, (c >> b) & 0x1);
    }
  }

  // Final flag
  uint8_t flag = 0x7E;
  for(int b=0;b<8;b++) setBit(bitBuf, totalBits++, (flag >> b) & 0x1);
}

unsigned long lastBeacon = 0;

void setup() {
  Serial.begin(115200);
  pinMode(PIN_PTT, OUTPUT);
  digitalWrite(PIN_PTT, LOW);
  // Prepare timer
  afskTimer = timerBegin(0, 80, true); // 80 MHz / 80 = 1 MHz tick
  timerAttachInterrupt(afskTimer, &onSampleTimer, true);
  timerAlarmWrite(afskTimer, SAMPLE_INTERVAL_US, true); // microseconds
  timerAlarmEnable(afskTimer);
  Serial.println("AX.25 AFSK TX scaffold ready");
}

void loop() {
  unsigned long now = millis();
  if(!transmitting && now - lastBeacon > BEACON_INTERVAL_MS) {
    enqueueTestFrame();
    startTransmit();
    lastBeacon = now;
    Serial.printf("Started frame: %u bits\n", (unsigned)totalBits);
  }
  if(!transmitting) {
    // Idle tasks (later: GPS read, sensors, etc.)
  }
}