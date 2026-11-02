// Waveform: a rectangle of music, driven by the microphone (the same one the BeatListener uses).
// Its settings are saved to wave.json with the s key and loaded when the show starts.
//
// Keys (press TAB until the wave canvas flashes)
//   1..5         look: 1 bars, 2 mirrored bars (from the middle), 3 line (oscilloscope),
//                4 blocks (LED meter), 5 square wave (the sound as a stepped, rectangular line)
//   , / .        fewer / more bars (also the number of steps in the square wave)
//   g            gap between bars: none, thin, wide
//   k            color: one color, rainbow, by height (cool at the bottom, hot at the top),
//                party (new color on every beat)
//   h            next color (for one color mode)
//   m            mirror: low notes in the middle, high notes out to both sides
//   d            smoothing: snappy, smooth, slow
//   b            flash brighter on the beat, on / off
//   o            outline around the rectangle, on / off
//   LEFT / RIGHT less / more sensitive
//   UP / DOWN    brighter / dimmer
//
// To change the shape of the canvas itself, change the numbers in WaveScene() below
// (or just stretch it with the corners while calibrating).

class WaveScene extends Scene {
  String[] LOOKS = {"", "bars", "mirrored bars", "line", "blocks", "square wave"};
  int look = 1;
  int bars = 48;
  int gapChoice = 1;                 // 0 none, 1 thin, 2 wide
  String[] COLOR_MODES = {"one color", "rainbow", "by height", "party"};
  int colorMode = 1;
  int colorIndex = 0;
  boolean mirror = false;
  int smoothChoice = 1;              // 0 snappy, 1 smooth, 2 slow
  boolean flash = true;
  boolean frame = false;
  float gain = 1.0;
  float level = 1.0;

  color[] COLORS = {
    color(80, 220, 255), color(255, 70, 160), color(255, 210, 60), color(120, 255, 120),
    color(180, 110, 255), color(255, 120, 40), color(255, 255, 255)
  };

  float[] values = new float[256];   // smoothed bar heights, 0..1
  float[] peaks = new float[256];    // little caps that fall slowly (blocks look)
  float[] demo = new float[1024];

  WaveScene() {
    super("wave", 1200, 300);
  }

  void setupScene() {
    if (new java.io.File(sketchPath("wave.json")).exists()) loadSettings();
  }

  void drawScene() {
    pg.hint(DISABLE_DEPTH_TEST);
    pg.background(0);
    pg.noStroke();

    if (look == 3 || look == 5) drawLine();
    else drawBars();

    if (frame) {
      pg.noFill();
      pg.stroke(barColor(0, 0.5));
      pg.strokeWeight(4);
      pg.rect(2, 2, W - 4, H - 4);
    }
  }

  // ---------- bars, mirrored bars, blocks ----------

  void drawBars() {
    int n = bars;
    updateBarValues(n);
    float gap = gapChoice == 0 ? 0 : (gapChoice == 1 ? 0.15 : 0.4);
    float slot = W / (float) n;
    float bw = slot * (1 - gap);

    for (int i = 0; i < n; i++) {
      // which frequency this bar shows: in mirror mode the lows sit in the middle
      int f = i;
      if (mirror) f = abs(i - (n - 1) / 2.0) < 0.5 ? 0 : (int) (abs(i - (n - 1) / 2.0) * 2);
      f = constrain(f, 0, n - 1);
      float v = values[f];
      float x = i * slot + (slot - bw) / 2;

      if (look == 1) {                                // bars up from the bottom
        float h = v * H;
        pg.fill(barColor(i / (float) n, v));
        pg.rect(x, H - h, bw, h);
      } else if (look == 2) {                         // bars out from the middle line
        float h = max(2, v * H);
        pg.fill(barColor(i / (float) n, v));
        pg.rect(x, (H - h) / 2, bw, h);
      } else {                                        // stacked blocks, like an LED meter
        int rows = 16;
        float rh = H / (float) rows;
        float bh = rh * (gapChoice == 0 ? 1 : 0.75);
        int lit = round(v * rows);
        for (int r = 0; r < lit; r++) {
          pg.fill(barColor(i / (float) n, (r + 1) / (float) rows));
          pg.rect(x, H - (r + 1) * rh + (rh - bh) / 2, bw, bh);
        }
        int pr = min(rows - 1, round(peaks[f] * rows));   // falling peak cap
        if (pr > 0) {
          pg.fill(barColor(i / (float) n, 1));
          pg.rect(x, H - (pr + 1) * rh + (rh - bh) / 2, bw, bh);
        }
      }
    }
  }

  // Splits the spectrum into n bars, spaced like a piano (each bar covers a bit more pitch range
  // than the one before), and turns loudness into a 0..1 height.
  void updateBarValues(int n) {
    float rise = 0.6;
    float fall = smoothChoice == 0 ? 0.35 : (smoothChoice == 1 ? 0.15 : 0.06);
    int lo = 1;
    int hi = 360;   // about 15 kHz; above that is mostly hiss
    for (int i = 0; i < n; i++) {
      int a = round(lo * pow(hi / (float) lo, i / (float) n));
      int b = max(a + 1, round(lo * pow(hi / (float) lo, (i + 1) / (float) n)));
      float sum = 0;
      for (int k = a; k < b; k++) sum += micOk ? spectrum[k] : demoBand(k);
      float avg = sum / (b - a);
      float tilt = 1 + 3 * i / (float) n;            // highs are naturally quieter; lift them
      float db = 20 * log(max(0.0000001, avg * gain * tilt)) / log(10);
      float target = constrain(map(db, -62, -12, 0, 1), 0, 1);
      values[i] = lerp(values[i], target, target > values[i] ? rise : fall);
      peaks[i] = max(values[i], peaks[i] - 0.008);
    }
  }

  // ---------- line and square wave ----------

  void drawLine() {
    float[] w = micOk && waveform != null ? waveform.analyze() : demoWave();
    int n = w.length;
    float mid = H / 2.0;
    float amp = H * 0.45 * gain * 3;
    pg.noFill();
    pg.strokeWeight(gapChoice == 2 ? 8 : (gapChoice == 1 ? 5 : 3));
    pg.strokeJoin(MITER);

    if (look == 3) {                                  // smooth oscilloscope line
      pg.beginShape();
      for (int i = 0; i < n; i++) {
        float x = map(i, 0, n - 1, 0, W);
        float y = mid - constrain(w[i] * amp, -mid, mid);
        pg.stroke(barColor(i / (float) n, abs(w[i]) * 3));
        pg.vertex(x, y);
      }
      pg.endShape();
    } else {                                          // square wave: one flat step per bar
      int steps = bars;
      float slot = W / (float) steps;
      float prevY = mid;
      for (int s = 0; s < steps; s++) {
        int a = s * n / steps;
        int b = (s + 1) * n / steps;
        float sum = 0;
        for (int i = a; i < b; i++) sum += w[i];
        float v = sum / max(1, b - a) * 4;           // average, scaled up (averaging shrinks it)
        float y = mid - constrain(v * amp, -mid + 6, mid - 6);
        pg.stroke(barColor(s / (float) steps, abs(v) * 3));
        pg.line(s * slot, prevY, s * slot, y);        // the vertical edge
        pg.line(s * slot, y, (s + 1) * slot, y);      // the flat top
        prevY = y;
      }
    }
    pg.noStroke();
  }

  // ---------- colors ----------

  // t = position across the canvas 0..1, v = how loud / how high 0..1
  color barColor(float t, float v) {
    color c;
    if (colorMode == 0) c = COLORS[colorIndex];
    else if (colorMode == 1) c = hsb(t * 0.85, 0.85, 1);
    else if (colorMode == 2) c = hsb(0.6 - 0.6 * constrain(v, 0, 1), 0.9, 1);   // blue -> red
    else c = COLORS[abs(beatCount()) % COLORS.length];

    float k = level;
    if (flash) k *= 0.65 + 0.35 * pow(1 - beatPhase(), 3);   // brightest right on the beat
    return color(red(c) * k, green(c) * k, blue(c) * k);
  }

  color hsb(float h, float s, float b) {
    return java.awt.Color.HSBtoRGB(h, s, b) | 0xFF000000;
  }

  // ---------- pretend music when there's no microphone, so you can still set it up ----------

  float demoBand(int k) {
    float kick = pow(1 - beatPhase(), 4);
    float n = noise(k * 0.15, millis() * 0.003);
    return (0.02 * n + (k < 8 ? 0.08 * kick : 0)) / (1 + k * 0.05);
  }

  float[] demoWave() {
    float kick = pow(1 - beatPhase(), 3);
    for (int i = 0; i < demo.length; i++) {
      float t = millis() * 0.001 + i / 44100.0;
      demo[i] = 0.12 * kick * sin(TWO_PI * 60 * t) + 0.03 * sin(TWO_PI * 220 * t)
                + 0.02 * (noise(i * 0.05, millis() * 0.01) - 0.5);
    }
    return demo;
  }

  // ---------- keys ----------

  void onKey() {
    if (key >= '1' && key <= '5') {
      look = key - '0';
      println("Wave look: " + LOOKS[look]);
    }
    if (key == ',' || key == '<') bars = max(4, round(bars / 1.25));
    if (key == '.' || key == '>') bars = min(200, round(bars * 1.25));
    if (key == ',' || key == '.' || key == '<' || key == '>') println("Wave bars: " + bars);
    if (key == 'g') gapChoice = (gapChoice + 1) % 3;
    if (key == 'k') {
      colorMode = (colorMode + 1) % COLOR_MODES.length;
      println("Wave color: " + COLOR_MODES[colorMode]);
    }
    if (key == 'h') {
      colorIndex = (colorIndex + 1) % COLORS.length;
      colorMode = 0;
    }
    if (key == 'm') mirror = !mirror;
    if (key == 'd') {
      smoothChoice = (smoothChoice + 1) % 3;
      println("Wave smoothing: " + new String[] {"snappy", "smooth", "slow"}[smoothChoice]);
    }
    if (key == 'b') flash = !flash;
    if (key == 'o') frame = !frame;
    if (key == CODED) {
      if (keyCode == UP)    level = min(1, level + 0.05);
      if (keyCode == DOWN)  level = max(0.1, level - 0.05);
      if (keyCode == RIGHT) gain *= 1.25;
      if (keyCode == LEFT)  gain /= 1.25;
      if (keyCode == LEFT || keyCode == RIGHT) println("Wave sensitivity: " + nf(gain, 0, 2));
    }
  }

  // ---------- save / load ----------

  void saveSettings() {
    JSONObject o = new JSONObject();
    o.setInt("look", look);
    o.setInt("bars", bars);
    o.setInt("gap", gapChoice);
    o.setInt("colorMode", colorMode);
    o.setInt("colorIndex", colorIndex);
    o.setBoolean("mirror", mirror);
    o.setInt("smoothing", smoothChoice);
    o.setBoolean("flash", flash);
    o.setBoolean("outline", frame);
    o.setFloat("sensitivity", gain);
    o.setFloat("brightness", level);
    saveJSONObject(o, sketchPath("wave.json"));
  }

  void loadSettings() {
    JSONObject o = loadJSONObject(sketchPath("wave.json"));
    look = o.getInt("look", look);
    bars = o.getInt("bars", bars);
    gapChoice = o.getInt("gap", gapChoice);
    colorMode = o.getInt("colorMode", colorMode);
    colorIndex = o.getInt("colorIndex", colorIndex);
    mirror = o.getBoolean("mirror", mirror);
    smoothChoice = o.getInt("smoothing", smoothChoice);
    flash = o.getBoolean("flash", flash);
    frame = o.getBoolean("outline", frame);
    gain = o.getFloat("sensitivity", gain);
    level = o.getFloat("brightness", level);
    println("Loaded wave settings");
  }
}
