// Poster Eyes: animated eyes and a light show projection mapped onto the poster.

class EyesScene extends Scene {
  color EYE_WHITE = color(255);

  // Background light over the whole poster
  color BG_TINT = color(255, 235, 210);   // warm white; try color(255) for pure white
  float bgLevel = 0.6;                    // 0 = off, 1 = full brightness (UP / DOWN arrows)
  boolean bgOn = true;                    // b toggles
  boolean flicker = false;                // f toggles a spooky candle flicker

  ArrayList<Eye> eyes = new ArrayList<Eye>();
  boolean editing = false;
  boolean followMouse = false;
  Eye selected = null;

  PVector gaze = new PVector(0, 0);        // where every eye is looking, -1..1
  PVector gazeTarget = new PVector(0, 0);
  int nextGlance = 0;

  // 1 steady light, 2 disco, 3 searchlight sweep, 4 spotlight hops between characters, 5 color pulse
  int mode = 1;
  int beatN = 0;
  int lastBeatN = -1;
  float phase = 0;             // 0..1 through the current beat
  float pulse = 0;             // 1 right on the beat, fades to 0

  color[] PALETTE = {
    color(255, 40, 160), color(40, 220, 255), color(255, 220, 40),
    color(80, 255, 90), color(255, 120, 30), color(150, 80, 255)
  };

  // Rough character centers and spotlight sizes as fractions of the poster (x, y, radius)
  float[][] CHARACTERS = {
    {0.31, 0.40, 0.28},   // square guy
    {0.69, 0.46, 0.25},   // blue cat
    {0.51, 0.73, 0.15},   // dog
    {0.52, 0.22, 0.08},   // spider
    {0.83, 0.82, 0.07}    // bird
  };
  int spotTarget = 0;
  PVector spotPos = new PVector(0, 0);
  float spotR = 100;

  // Poster canvas size. Keep the same proportions as your real poster.
  EyesScene() {
    super("eyes", 600, 760);
  }

  void setupScene() {
    // this sketch's own eyes.json, or the one saved from poster_eyes
    String[] tries = {sketchPath("eyes.json"), sketchPath("../eyes.json")};
    for (String f : tries) {
      if (new java.io.File(f).exists()) {
        loadEyes(f);
        println("Loaded eyes from " + f);
        return;
      }
    }
    defaultEyes();
  }

  void drawScene() {
    updateBeat();
    updateGaze();
    pg.hint(DISABLE_DEPTH_TEST);
    drawBackground();
    for (Eye e : eyes) {
      e.update();
      e.draw(pg, gaze, EYE_WHITE);
    }
    if (editing) drawEditOverlay();
  }

  // ---------- background light ----------

  color backgroundColor() {
    if (!bgOn) return color(0);
    float level = bgLevel;
    if (flicker) {
      level *= 0.75 + 0.25 * noise(millis() * 0.004);   // slow wobble
      if (random(1) < 0.01) level *= 0.4;               // occasional dip
    }
    return color(red(BG_TINT) * level, green(BG_TINT) * level, blue(BG_TINT) * level);
  }

  // ---------- beat (from the show's shared beat) ----------

  void updateBeat() {
    beatN = beatCount();
    phase = beatPhase();
    pulse = pow(1 - phase, 3);
    if (beatN != lastBeatN) {
      lastBeatN = beatN;
      onBeat();
    }
  }

  void onBeat() {
    // spotlight jumps to a different character
    int next = (int) random(CHARACTERS.length);
    if (next == spotTarget) next = (next + 1) % CHARACTERS.length;
    spotTarget = next;
  }

  // ---------- backgrounds ----------

  void drawBackground() {
    if (mode == 1) {
      pg.background(backgroundColor());
      return;
    }

    // dim base light so the poster never goes fully dark
    float base = bgOn ? bgLevel * 0.15 : 0;
    pg.background(red(BG_TINT) * base, green(BG_TINT) * base, blue(BG_TINT) * base);
    pg.blendMode(ADD);

    if (mode == 2) {                               // disco: colored lights roaming around
      float t = millis() * 0.0004;
      for (int i = 0; i < 5; i++) {
        float x = noise(i * 37.1, t) * W * 1.4 - W * 0.2;
        float y = noise(i * 91.7, t + 100) * H * 1.4 - H * 0.2;
        softCircle(x, y, W * 0.35, PALETTE[i], 0.35 + 0.45 * pulse);
      }
    } else if (mode == 3) {                        // searchlight sweeping left and right
      float x = W / 2.0 + sin((beatN + phase) * PI) * W * 0.45;
      softBand(x, W * 0.35, BG_TINT, 0.6 + 0.3 * pulse);
    } else if (mode == 4) {                        // spotlight hops between characters
      float[] c = CHARACTERS[spotTarget];
      spotPos.lerp(c[0] * W, c[1] * H, 0, 0.25);
      spotR = lerp(spotR, c[2] * W, 0.25);
      softCircle(spotPos.x, spotPos.y, spotR * 1.3, BG_TINT, 0.7 + 0.3 * pulse);
    } else if (mode == 5) {                        // whole poster pulses a new color each beat
      color c = PALETTE[abs(beatN) % PALETTE.length];
      float lv = 0.2 + 0.6 * pulse;
      pg.noStroke();
      pg.fill(red(c) * lv, green(c) * lv, blue(c) * lv);
      pg.rect(0, 0, W, H);
    }

    pg.blendMode(BLEND);
  }

  void softCircle(float x, float y, float r, color c, float strength) {
    pg.noStroke();
    for (int i = 10; i >= 1; i--) {
      float rr = r * i / 10.0;
      pg.fill(red(c), green(c), blue(c), 255 * strength / 10.0);
      pg.ellipse(x, y, rr * 2, rr * 2);
    }
  }

  void softBand(float x, float w, color c, float strength) {
    pg.noStroke();
    for (int i = 10; i >= 1; i--) {
      float ww = w * i / 10.0;
      pg.fill(red(c), green(c), blue(c), 255 * strength / 10.0);
      pg.rect(x - ww / 2, 0, ww, H);
    }
  }

  // ---------- gaze ----------

  void updateGaze() {
    float speed = 0.15;
    if (followMouse) {
      PVector m = surface.getTransformedMouse();
      gazeTarget.set(constrain((m.x - W / 2.0) / (W / 2.0), -1, 1),
                     constrain((m.y - H / 2.0) / (H / 2.0), -1, 1));
    } else if (mode > 1) {
      // dancing: eyes snap left and right on every beat
      gazeTarget.set(beatN % 2 == 0 ? -0.9 : 0.9, -0.2);
      speed = 0.35;
    } else if (millis() > nextGlance) {
      gazeTarget.set(random(-1, 1), random(-1, 1));
      nextGlance = millis() + (int) random(800, 3000);
    }
    gaze.lerp(gazeTarget, speed);
  }

  // ---------- starting positions (rough guesses from the photo, fix them in edit mode) ----------

  void defaultEyes() {
    // x, y, width, height as fractions of the poster, then the eyelid color
    addEye(0.222, 0.290, 0.100, 0.135, color(240, 220, 180)); // square guy, big eye
    addEye(0.598, 0.370, 0.096, 0.085, color(90, 110, 200));  // blue cat
    addEye(0.300, 0.157, 0.020, 0.016, color(120, 190, 190)); // crown guy, left
    addEye(0.333, 0.157, 0.020, 0.016, color(120, 190, 190)); // crown guy, right
    addEye(0.512, 0.227, 0.030, 0.022, color(230, 140, 150)); // spider
    addEye(0.451, 0.677, 0.018, 0.014, color(230, 140, 100)); // dog, left
    addEye(0.470, 0.681, 0.018, 0.014, color(230, 140, 100)); // dog, right
    addEye(0.874, 0.811, 0.012, 0.010, color(170, 210, 120)); // bird
  }

  void addEye(float fx, float fy, float fw, float fh, color lid) {
    eyes.add(new Eye(fx * W, fy * H, fw * W, fh * H, lid));
  }

  // ---------- editing ----------

  void drawEditOverlay() {
    pg.noFill();
    pg.strokeWeight(2);
    pg.stroke(0, 255, 0);
    pg.rect(1, 1, W - 2, H - 2);           // poster outline
    for (Eye e : eyes) {
      pg.stroke(e == selected ? color(255, 255, 0) : color(0, 255, 0));
      pg.ellipse(e.x, e.y, e.w, e.h);
    }
  }

  void onMousePressed() {
    PVector m = surface.getTransformedMouse();
    selected = null;
    for (Eye e : eyes) {
      if (dist(m.x, m.y, e.x, e.y) < max(e.w, e.h) / 2 + 6) selected = e;
    }
  }

  void onMouseDragged() {
    if (selected != null) {
      PVector m = surface.getTransformedMouse();
      selected.x = m.x;
      selected.y = m.y;
    }
  }

  void onKey() {
    if (key == 'e') {
      editing = !editing;
      if (calibrating) {
        ks.toggleCalibration();
        calibrating = false;
      }
    }
    if (key == 'm') followMouse = !followMouse;
    if (key >= '1' && key <= '5') mode = key - '0';
    if (key == 'b') bgOn = !bgOn;
    if (key == 'f') flicker = !flicker;
    if (key == CODED) {
      if (keyCode == UP)   bgLevel = min(1, bgLevel + 0.05);
      if (keyCode == DOWN) bgLevel = max(0, bgLevel - 0.05);
    }

    if (editing && key == 'n') {
      PVector m = surface.getTransformedMouse();
      selected = new Eye(m.x, m.y, 30, 30, color(255));
      eyes.add(selected);
    }

    if (editing && selected != null) {
      if (key == ']') { selected.w *= 1.05; selected.h *= 1.05; }
      if (key == '[') { selected.w /= 1.05; selected.h /= 1.05; }
      if (key == '.') selected.w *= 1.05;
      if (key == ',') selected.w /= 1.05;
      if (key == '=') selected.h *= 1.05;
      if (key == '-') selected.h /= 1.05;
      if (key == 'x') {
        eyes.remove(selected);
        selected = null;
      }
    }
  }

  // ---------- save / load ----------

  void saveEyes() {
    JSONArray arr = new JSONArray();
    for (Eye e : eyes) {
      JSONObject o = new JSONObject();
      o.setFloat("x", e.x);
      o.setFloat("y", e.y);
      o.setFloat("w", e.w);
      o.setFloat("h", e.h);
      o.setInt("lid", e.lidColor);
      arr.append(o);
    }
    saveJSONArray(arr, sketchPath("eyes.json"));
  }

  void loadEyes(String file) {
    JSONArray arr = loadJSONArray(file);
    for (int i = 0; i < arr.size(); i++) {
      JSONObject o = arr.getJSONObject(i);
      eyes.add(new Eye(o.getFloat("x"), o.getFloat("y"),
                       o.getFloat("w"), o.getFloat("h"), o.getInt("lid")));
    }
  }
}

// ---------- eye ----------

class Eye {
  float x, y, w, h;
  color lidColor;
  float blink = 0;          // 0 = open, 1 = closed
  boolean blinking = false;
  int blinkStart;
  int nextBlink;

  Eye(float x, float y, float w, float h, color lidColor) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.lidColor = lidColor;
    nextBlink = millis() + (int) random(1500, 6000);
  }

  void update() {
    int now = millis();
    if (!blinking && now > nextBlink) {
      blinking = true;
      blinkStart = now;
    }
    if (blinking) {
      float t = (now - blinkStart) / 90.0;   // 90 ms to close, 90 ms to open
      blink = t < 1 ? t : 2 - t;
      if (t >= 2) {
        blinking = false;
        blink = 0;
        nextBlink = now + (int) random(2000, 7000);
      }
    }
  }

  void draw(PGraphics g, PVector gaze, color white) {
    g.noStroke();
    float open = 1 - blink;

    if (blink > 0) {                     // eyelid
      g.fill(lidColor);
      g.ellipse(x, y, w, h);
    }
    if (open > 0.05) {
      float eh = h * open;
      float ey = y + (h - eh) / 2;       // lid closes from the top
      g.fill(white);
      g.ellipse(x, ey, w, eh);

      float pd = min(w, eh) * 0.5;       // pupil
      float px = x + gaze.x * (w - pd) * 0.35;
      float py = ey + gaze.y * (eh - pd) * 0.35;
      g.fill(0);
      g.ellipse(px, py, pd, pd);
    }
  }
}
