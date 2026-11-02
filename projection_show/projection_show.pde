// Projection Show: the poster eyes, the dancing bear and a music waveform in one sketch.
// Each one is its own canvas with its own four corners, so you can place them anywhere
// on the projector and turn each one on or off. They all follow one shared beat, which the
// sketch works out by listening to the music through the microphone (see the BeatListener tab).
//
// Each scene is in its own tab: Eyes, Bear, Wave. Scene has the parts they share.
//
// Keys for the whole show
//   7 / 8 / 9  show or hide the eyes / bear / wave
//   TAB    choose which canvas gets the scene keys below (it flashes a green outline)
//   l      listen for the beat through the microphone, on / off (on when it starts)
//   t      tap along to the music (4 or more taps) to set the beat yourself; this turns listening off
//   + / -  nudge the tempo up or down
//   [ / ]  beat a little earlier / later, if the dancing looks behind or ahead of the music
//   c      Keystone calibration: drag the corners of each canvas into place
//          (hidden canvases show up while calibrating, so you can still place them)
//   s      save the corners (keystone.xml), the eyes (eyes.json) and the wave settings (wave.json)
//   p      snap the window back onto the projector display
//
// Keys for the chosen canvas
//   Eyes    1..5 light show (1 steady, 2 disco, 3 searchlight, 4 spotlight hops, 5 color pulse)
//           b background light, f candle flicker, m eyes follow the mouse, UP / DOWN brightness
//           e edit eyes: click to select, drag to move, [ ] size, , . width, - = height,
//             n new eye at the mouse, x delete
//   Bear    0 auto, 1..5 moves (bop, raise the roof, stomp, sway, jump), SPACE pause,
//           i glow or paper, k party colors, w wobbly lines, UP / DOWN brightness
//   Wave    1..5 look (bars, mirrored bars, line, blocks, square wave), , . fewer / more bars,
//           g gap, k color mode, h next color, m mirror, d smoothing, b flash on the beat,
//           o outline, LEFT / RIGHT sensitivity, UP / DOWN brightness (more in the Wave tab)

import deadpixel.keystone.*;

Keystone ks;
Scene[] scenes;
EyesScene eyesScene;
WaveScene waveScene;
int selectedScene = 0;
int selectedAt = -10000;
boolean calibrating = false;

// Shared beat
float bpm = 110;
int beatOrigin = 0;
ArrayList<Integer> taps = new ArrayList<Integer>();

// Which display to go fullscreen on. 1 = main display (the one with the menu bar),
// 2 = second display (projector), and so on. 0 = pick automatically:
// the projector if one is connected, otherwise the main display.
int DISPLAY = 0;
java.awt.Rectangle screenBounds;   // position and size of that display in macOS screen coordinates

// fullScreen() / pixelDensity() have to go in settings() when they depend on variables.
void settings() {
  java.awt.GraphicsDevice[] screens =
    java.awt.GraphicsEnvironment.getLocalGraphicsEnvironment().getScreenDevices();
  for (int i = 0; i < screens.length; i++) {
    java.awt.Rectangle b = screens[i].getDefaultConfiguration().getBounds();
    println("Display " + (i + 1) + ": " + b.width + " x " + b.height + " at " + b.x + ", " + b.y);
  }
  int d = DISPLAY > 0 ? DISPLAY : screens.length;   // auto: use the last display (the projector)
  d = constrain(d, 1, screens.length);
  screenBounds = screens[d - 1].getDefaultConfiguration().getBounds();
  println("Going fullscreen on display " + d);

  // P3D on macOS doesn't place fullscreen windows on other displays correctly,
  // so open borderless fullscreen on the main display, then move and resize it.
  fullScreen(P3D, 1);
  pixelDensity(1);
}

// Moves the borderless window onto the chosen display and makes it fill that display.
// Runs on its own thread (via thread()) because resizing/moving a P3D window from inside
// setup() or draw() can deadlock on macOS.
void moveToTargetDisplay() {
  delay(500);   // give the window a moment to finish opening
  getSurface().setResizable(true);
  getSurface().setLocation(screenBounds.x, screenBounds.y);
  getSurface().setSize(screenBounds.width, screenBounds.height);
  println("Moved window to " + screenBounds.x + ", " + screenBounds.y +
          " size " + screenBounds.width + " x " + screenBounds.height);
}

void setup() {
  thread("moveToTargetDisplay");

  ks = new Keystone(this);
  eyesScene = new EyesScene();
  waveScene = new WaveScene();
  scenes = new Scene[] {eyesScene, new BearScene(), waveScene};
  for (Scene s : scenes) s.init();   // the order here is the order of the corners in keystone.xml

  // Canvases without saved corners (all of them on the first run, or one you just added)
  // start lined up side by side; press c to place them, then s to save.
  int saved = 0;
  String cornersFile = sketchPath("keystone.xml");
  if (new java.io.File(cornersFile).exists()) {
    saved = loadXML(cornersFile).getChildren("surface").length;
  }
  float x = 40;
  for (int i = 0; i < scenes.length; i++) {
    if (i >= saved) scenes[i].surface.moveTo(x, 40 + 60 * i);
    x += 200;
  }
  if (saved > scenes.length) {
    println("keystone.xml has more canvases than the show; ignoring it. Press c to place them, s to save.");
  } else if (saved > 0) {
    ks.load(cornersFile);
    println("Loaded corners" + (saved < scenes.length ? " (new canvases still need placing: press c)" : ""));
  } else {
    println("No saved corners yet: press c, drag each canvas into place, then s to save");
  }
  startListening();
}

void draw() {
  listenForBeat();
  background(0);
  for (int i = 0; i < scenes.length; i++) {
    Scene s = scenes[i];
    if (!s.visible && !calibrating) continue;
    s.pg.beginDraw();
    s.drawScene();
    if (i == selectedScene && millis() - selectedAt < 1500) {   // flash an outline on the chosen canvas
      s.pg.hint(DISABLE_DEPTH_TEST);
      s.pg.noTint();
      s.pg.noFill();
      s.pg.stroke(0, 255, 0);
      s.pg.strokeWeight(8);
      s.pg.rect(4, 4, s.W - 8, s.H - 8);
    }
    s.pg.endDraw();
    s.surface.render(s.pg);
  }
}

// ---------- shared beat ----------

float beatMs()    { return 60000.0 / bpm; }
float beatPhase() {
  float m = beatMs();
  return (((millis() - beatOrigin) % m) + m) % m / m;
}
int beatCount()   { return floor((millis() - beatOrigin) / beatMs()); }

void tapTempo() {
  int now = millis();
  if (!taps.isEmpty() && now - taps.get(taps.size() - 1) > 2000) taps.clear();
  taps.add(now);
  if (taps.size() > 6) taps.remove(0);
  if (taps.size() >= 2) {
    float avg = (taps.get(taps.size() - 1) - taps.get(0)) / (float) (taps.size() - 1);
    bpm = 60000.0 / avg;
  }
  beatOrigin = now;
  println("BPM: " + nf(bpm, 0, 1));
}

// ---------- keys and mouse ----------

void keyPressed() {
  Scene sel = scenes[selectedScene];
  boolean eyesEditing = sel == eyesScene && eyesScene.editing;

  if (key == TAB) {
    selectedScene = (selectedScene + 1) % scenes.length;
    selectedAt = millis();
    println("Keys now go to the " + scenes[selectedScene].name);
    return;
  }
  if (key >= '7' && key < '7' + scenes.length) {
    Scene s = scenes[key - '7'];
    s.visible = !s.visible;
    println(s.name + (s.visible ? " on" : " off"));
    return;
  }
  if (key == 'c') {
    calibrating = !calibrating;
    ks.toggleCalibration();
    eyesScene.editing = false;
    return;
  }
  if (key == 's') {
    ks.save(sketchPath("keystone.xml"));
    eyesScene.saveEyes();
    waveScene.saveSettings();
    println("Saved corners, eyes and wave settings");
    return;
  }
  if (key == 'p') {
    thread("moveToTargetDisplay");   // re-snap the window onto the projector
    return;
  }
  if (key == 't') {
    if (listening) println("Listening off: you're tapping now (l to listen again)");
    listening = false;
    tapTempo();
    return;
  }
  if (key == 'l') {
    if (!micOk) startListening();
    else listening = !listening;
    println(listening ? "Listening for the beat" : "Listening off");
    return;
  }
  if (!eyesEditing) {   // while editing eyes, - = [ ] change the selected eye instead
    if (key == '[' || key == ']') {
      LATENCY_MS += key == '[' ? 10 : -10;
      println("Beat lands " + LATENCY_MS + " ms before the mic hears it");
      return;
    }
    if (key == '+' || key == '=') {
      bpm += 2;
      println("BPM: " + nf(bpm, 0, 1));
      return;
    }
    if (key == '-' || key == '_') {
      bpm = max(40, bpm - 2);
      println("BPM: " + nf(bpm, 0, 1));
      return;
    }
  }
  sel.onKey();
}

void mousePressed() {
  if (eyesScene.editing) eyesScene.onMousePressed();
}

void mouseDragged() {
  if (eyesScene.editing) eyesScene.onMouseDragged();
}
