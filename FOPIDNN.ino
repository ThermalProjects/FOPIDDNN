#include <Arduino.h>
#include <Wire.h>
#include <SensirionI2cScd4x.h>
#include <math.h>

// ================== PINS ==================
#define TERM_PIN A0
#define PELTIER_PIN 6
#define FAN_PIN 5

SensirionI2cScd4x scd4x;

// ================== CONFIG ==================
const int MAX_PWM_SAFE = 220;
float Ts = 0.1;
const bool USE_RAMP = true;

// ======== BIAS TÉRMICO ========
const float THERMAL_BIAS = 0.4;

// ================== ESTADO ==================
float Tsup = 0;
float Tsup_raw = 0;
float Tsup_filt = 0;
float Tsup_vis = 0;

float Tamb = 0, RH = 0, Tref = 25.0, Tdew = 0;

int pwmPeltier = 0, pwmFan = 0;
int pwmPeltierTarget = 0;

bool controlEnabled = false;
bool fanManual = false;
int pwmFanManual = 0;
bool showTdew = false;

// ================== FILTRO ==================
const float alpha = 0.02;

// ================== VISUAL ==================
const float VISUAL_HYST = 0.1;

// ================== FOPID ==================
#define M 30
#define I_MAX 25.0

float e_hist[M + 1];
float wI[M + 1];
float wD[M + 1];

float Kp = 58.93;
float Ki = 3.91;
float Kd = 2.66;
float Kff = 0;
float lambda = 0.67;
float mu = 1.47;

unsigned long lastReadTime = 0;

// ================== INIT GL ==================
void initGL() {
  wI[0] = 1.0;
  wD[0] = 1.0;

  for (int k = 1; k <= M; k++) {
    wI[k] = wI[k - 1] * ((lambda - (k - 1)) / k);
    wD[k] = wD[k - 1] * ((mu - (k - 1)) / k);
  }

  for (int i = 0; i <= M; i++) e_hist[i] = 0;
}

// ================== TERMISTOR ==================
float leerTermistorRaw() {
  long suma = 0;
  for (int i = 0; i < 10; i++) {
    suma += analogRead(TERM_PIN);
    delayMicroseconds(50);
  }
  float valADC = (float)suma / 10.0;
  float V = (valADC * 3.3) / 4095.0;
  if (V < 0.01) V = 0.01;
  
  float Rth = 10000.0 * (3.3 / V - 1.0);
  float T = 1.0 / (1.0 / 298.15 + log(Rth / 10000.0) / 3435.0);
  return T - 273.15;
}
// ================== PWM ==================
void applyPWM() {
  if (USE_RAMP) {
    float diffErr = Tsup - (showTdew ? Tdew : (Tref - THERMAL_BIAS));
    int step = (diffErr > 0.1) ? 8 : 1;

    if (pwmPeltier < pwmPeltierTarget)
      pwmPeltier = min(pwmPeltier + step, pwmPeltierTarget);
    else if (pwmPeltier > pwmPeltierTarget)
      pwmPeltier = max(pwmPeltier - step, pwmPeltierTarget);
  } else {
    pwmPeltier = pwmPeltierTarget;
  }

// Si Kff > 0, la IA nos da permiso de usar el "Boost" hasta 255
  int limiteActual = (Kff > 0.1) ? 255 : MAX_PWM_SAFE; 
  analogWrite(PELTIER_PIN, constrain(pwmPeltier, 0, limiteActual));

  if (fanManual) pwmFan = pwmFanManual;
  else pwmFan = (pwmPeltier > 20) ? 255 : 0;

  analogWrite(FAN_PIN, pwmFan);
}

// ================== SETUP ==================
void setup() {
  Serial.begin(115200);
  pinMode(PELTIER_PIN, OUTPUT);
  pinMode(FAN_PIN, OUTPUT);
  analogReadResolution(12);
  Wire.begin();
  scd4x.begin(Wire, 0x62);
  scd4x.startPeriodicMeasurement();

  Tsup_raw = leerTermistorRaw();
  Tsup_filt = Tsup_raw;
  Tsup = Tsup_filt;
  Tsup_vis = Tsup;

  initGL();
  lastReadTime = millis();
}

// ================== LOOP ==================
void loop() {
  if (millis() - lastReadTime >= (unsigned long)(Ts * 1000)) {
    lastReadTime = millis();

    // --- Termistor ---
// --- Termistor con Filtro Defensivo ---
    Tsup_raw = leerTermistorRaw();
    if (fabs(Tsup_raw - Tsup_filt) < 0.15) {
        Tsup_filt += alpha * (Tsup_raw - Tsup_filt);
    } else {
        Tsup_filt += (alpha * 0.1) * (Tsup_raw - Tsup_filt);
    }
    Tsup = Tsup_filt;

    // --- SCD4x ---
    static int scdCounter = 0;
    if (scdCounter++ % 20 == 5) {
      uint16_t co2; float t, h;
      if (scd4x.readMeasurement(co2, t, h) == 0) {
        Tamb = t;
        RH = h;
      }
    }

    if (RH > 0) {
      Tdew = 243.5 * (log(RH / 100.0) + (17.67 * Tamb) / (243.5 + Tamb)) /
             (17.67 - (log(RH / 100.0) + (17.67 * Tamb) / (243.5 + Tamb)));
    }

    // --- Control ---
    float target = showTdew ? Tdew : (Tref - THERMAL_BIAS);
    float e = Tsup - target;

    for (int i = M; i > 0; i--) e_hist[i] = e_hist[i - 1];
    e_hist[0] = e;

    if (controlEnabled) {
      float sumI = 0, sumD = 0;

      for (int k = 0; k <= M; k++) {
        sumI += wI[k] * e_hist[k];
        sumD += wD[k] * e_hist[k];
      }

      sumI = constrain(sumI, -I_MAX, I_MAX);
      float sumD_reg = sumD / (1.0 + fabs(sumD));

      float u = (Kp * e)
              + Ki * pow(Ts, lambda) * sumI
              + Kd * (sumD_reg / pow(Ts, mu))
              + (Kff * target);

      pwmPeltierTarget = constrain((int)u, 0, 255);
    } else {
      pwmPeltierTarget = 0;
    }

    applyPWM();

    // --- Visual ---
    if (fabs(Tsup - Tsup_vis) >= VISUAL_HYST)
      Tsup_vis = Tsup;

 
    Serial.print(Tamb, 1); Serial.print(",");
    Serial.print(Tsup, 1); Serial.print(",");
    Serial.print(RH, 1); Serial.print(",");
    Serial.print(Tdew, 1); Serial.print(",");
    Serial.print(pwmPeltier); Serial.print(",");
    Serial.println(pwmFan);
  }

  // --- Comandos ---
  if (Serial.available()) {
    String line = Serial.readStringUntil('\n');
    line.trim();

    if (line.startsWith("SET_TREF")) {
      Tref = line.substring(line.indexOf(',') + 1).toFloat();
      initGL();
    }
    else if (line.equals("FOPID_ON")) {
      controlEnabled = true;
      initGL();
    }
    else if (line.equals("FOPID_OFF")) {
      controlEnabled = false;
      pwmPeltierTarget = 0;
    }
    else if (line.startsWith("PWM_MANUAL_FAN")) {
      int c = line.indexOf(',');
      pwmFanManual = (c > 0) ? line.substring(c + 1).toInt() : 255;
      fanManual = true;
    }
    else if (line.equals("FAN_OFF")) {
      fanManual = true;
      pwmFanManual = 0;
    }
    else if (line.equals("FAN_MANUAL_OFF")) {
      fanManual = false;
    }
    else if (line.equals("MODE_TDEW_ON")) showTdew = true;
    else if (line.equals("MODE_TDEW_OFF")) showTdew = false;
    
    // ----- COMUNICACIÓN CON LA NN (AÑADIDO) -----
    else if (line.startsWith("SET_KP")) Kp = line.substring(7).toFloat();
    else if (line.startsWith("SET_KI")) Ki = line.substring(7).toFloat();
    else if (line.startsWith("SET_KD")) Kd = line.substring(7).toFloat();
    else if (line.startsWith("SET_KFF")) { Kff = line.substring(8).toFloat(); }
    else if (line.startsWith("SET_LAMBDA")) { lambda = line.substring(11).toFloat(); initGL(); }
    else if (line.startsWith("SET_MU")) { mu = line.substring(7).toFloat(); initGL(); }
    // --------------------------------------------
  }
}
