// Dancing Zombie: your zombie picture, cut into parts (head, torso, arms, legs) that dance to the beat.
// The parts are in the data folder, with their positions and joints in zombie_rig.json.
//
// Keys
//   t      tap along to the music (4 or more taps) to set the beat
//   + / -  nudge the tempo up or down
//   0      auto: switch dance move every 8 beats
//   1..5   pick a move: 1 shamble, 2 zombie reach, 3 head bang, 4 side shuffle, 5 hop
//   SPACE  pause dancing (he just stands and sways)
//   k      party colors: he gets tinted a new color on every beat
//   r      turning around on the beat: every 4 beats -> every 2 -> every beat -> off
//   f      flip him to face the other way
//   UP / DOWN  brighter / dimmer
//   c      Keystone calibration (drag the corners to place him on the wall)
//   s      save the corners (keystone.xml)
//   p      snap the window back onto the projector display

import deadpixel.keystone.*;

Keystone ks;
CornerPinSurface surface;
PGraphics pg;

// Canvas for the zombie. Same 3:4 shape as the bear, so the bear's saved corners fit.
int W = 900;
int H = 1200;
float groundY = 1170;

// Picture -> canvas
float zScale = 0.66;
float FOOT_Y = 1595;     // bottom of the shoes in the picture, in picture pixels
float CENTER_X = 600;    // picture x that sits in the middle of the canvas
boolean flip = false;

// Turning around on the beat
int[] TURN_EVERY = {4, 2, 1, 0};   // beats between turns, 0 = off (r key cycles)
int turnChoice = 0;
float facing = 1;                  // 1 = faces left like the picture, -1 = faces right, in between mid-turn

// Parts, from data/zombie_rig.json
class Part {
  PImage img;
  float x, y;      // top left corner in the picture
  float px, py;    // joint it turns around, in picture pixels
}
HashMap<String, Part> parts = new HashMap<String, Part>();

// Look
boolean party = false;
float level = 1.0;
color[] PARTY = {
  color(255, 90, 150), color(90, 210, 255), color(255, 215, 70),
  color(180, 120, 255), color(90, 255, 150)
};

// Beat
float bpm = 110;
int beatOrigin = 0;
ArrayList<Integer> taps = new ArrayList<Integer>();

// Dance
int move = 0;   // 0 = auto
boolean dancing = true;
String[] MOVES = {"auto", "shamble", "zombie reach", "head bang", "side shuffle", "hop"};
Pose pose = new Pose();
Pose target = new Pose();

boolean calibrating = false;

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
// Note: this sketch's "surface" variable is the Keystone surface, so use getSurface() for the window.
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

  loadRig();

  ks = new Keystone(this);
  surface = ks.createCornerPinSurface(W, H, 20);
  pg = createGraphics(W, H, P3D);
  loadCorners();
}

// Uses this sketch's own keystone.xml if you've saved one (s key).
// Otherwise borrows the corners from the bear, or from poster_eyes, so he starts in the same spot.
void loadCorners() {
  String[] tries = {
    sketchPath("keystone.xml"),
    sketchPath("../dancing_bear/keystone.xml"),
    sketchPath("../keystone.xml")
  };
  for (String f : tries) {
    if (new java.io.File(f).exists()) {
      ks.load(f);
      println("Loaded corners from " + f);
      return;
    }
  }
  println("No saved corners yet: press c, drag the corners into place, then s to save");
}

void loadRig() {
  JSONObject rig = loadJSONObject("zombie_rig.json");
  JSONArray list = rig.getJSONArray("parts");
  for (int i = 0; i < list.size(); i++) {
    JSONObject o = list.getJSONObject(i);
    Part p = new Part();
    p.img = loadImage(o.getString("file"));
    p.x = o.getFloat("x");
    p.y = o.getFloat("y");
    p.px = o.getFloat("pivotX");
    p.py = o.getFloat("pivotY");
    parts.put(o.getString("name"), p);
  }
}

void draw() {
  danceTargets();
  pose.lerpTo(target, 0.25);
  updateFacing();

  pg.beginDraw();
  pg.hint(DISABLE_DEPTH_TEST);   // draw in painter's order
  pg.background(0);
  pg.imageMode(CORNER);
  pg.tint(tintColor());

  pg.pushMatrix();
  // picture coordinates from here on, feet on the ground line, squash and stretch from the feet
  pg.translate(W / 2.0, groundY);
  float turning = 1 - abs(facing);   // 1 halfway through a turn
  pg.scale(zScale * facing * (2 - pose.squash), zScale * (pose.squash + 0.04 * turning));
  pg.translate(-CENTER_X + pose.shiftX, -FOOT_Y + pose.hopY - 40 * turning);   // little hop as he spins

  // back to front
  pushTorso();
  drawPart("back_arm", pose.backArm);
  pg.popMatrix();

  drawLeg("left_leg", pose.legL, pose.liftL);
  drawLeg("right_leg", pose.legR, pose.liftR);

  pushTorso();
  drawPart("torso", 0);
  drawPart("front_arm", pose.frontArm);
  drawPart("head", pose.head);
  pg.popMatrix();

  pg.popMatrix();
  pg.noTint();
  pg.endDraw();

  background(0);
  surface.render(pg);
}

// The torso, arms and head all move with the hips
void pushTorso() {
  Part t = parts.get("torso");
  pg.pushMatrix();
  pg.translate(pose.bodyX, pose.bodyY);
  pg.translate(t.px, t.py);
  pg.rotate(pose.lean);
  pg.translate(-t.px, -t.py);
}

// draws a part turned by ang (radians) around its joint
void drawPart(String name, float ang) {
  Part p = parts.get(name);
  pg.pushMatrix();
  pg.translate(p.px, p.py);
  pg.rotate(ang);
  pg.image(p.img, p.x - p.px, p.y - p.py);
  pg.popMatrix();
}

// legs are stiff (he's a zombie): they swing from the hip and lift straight up
void drawLeg(String name, float ang, float lift) {
  pg.pushMatrix();
  pg.translate(0, -lift);
  drawPart(name, ang);
  pg.popMatrix();
}

color tintColor() {
  color c = color(255);
  if (party) c = lerpColor(c, PARTY[beatCount() % PARTY.length], 0.45);
  return color(red(c) * level, green(c) * level, blue(c) * level);
}

// ---------- pose ----------
// Angles are in radians. Positive turns clockwise on screen: for an arm or leg that swings
// it forward (to the left, the way he faces); for the head and body it leans them back.
// Distances are in picture pixels.

class Pose {
  float shiftX, hopY, squash;    // whole zombie
  float bodyX, bodyY, lean;      // torso, arms and head
  float head, backArm, frontArm;
  float legL, legR, liftL, liftR;

  Pose() {
    reset();
  }

  void reset() {
    shiftX = 0;
    hopY = 0;
    squash = 1;
    bodyX = 0;
    bodyY = 0;
    lean = 0;
    head = 0;
    backArm = 0;
    frontArm = 0;
    legL = 0;
    legR = 0;
    liftL = 0;
    liftR = 0;
  }

  void lerpTo(Pose t, float k) {
    shiftX = lerp(shiftX, t.shiftX, k);
    hopY = lerp(hopY, t.hopY, k);
    squash = lerp(squash, t.squash, k);
    bodyX = lerp(bodyX, t.bodyX, k);
    bodyY = lerp(bodyY, t.bodyY, k);
    lean = lerp(lean, t.lean, k);
    head = lerp(head, t.head, k * 0.8);          // the head and arms lag a little, so they flop
    backArm = lerp(backArm, t.backArm, k * 0.7);
    frontArm = lerp(frontArm, t.frontArm, k * 0.7);
    legL = lerp(legL, t.legL, k);
    legR = lerp(legR, t.legR, k);
    liftL = lerp(liftL, t.liftL, k);
    liftR = lerp(liftR, t.liftR, k);
  }
}

// ---------- dance moves ----------

void danceTargets() {
  Pose t = target;
  t.reset();
  float ms = millis();

  if (!dancing) {   // idle: slow zombie sway
    t.lean = 0.03 * sin(ms * 0.0011);
    t.head = -0.05 + 0.06 * sin(ms * 0.0009 + 1);
    t.backArm = 0.05 * sin(ms * 0.0011 + 2);
    t.frontArm = 0.05 * sin(ms * 0.0011 + 2.4);
    t.bodyY = 3 * sin(ms * 0.002);
    return;
  }

  float b = beatPhase();
  int n = beatCount();
  float two = ((n % 2) + b) / 2.0;        // 0..1 across two beats
  float s2 = sin(TWO_PI * two);
  float bob = sq(cos(PI * b));            // 1 on the beat, 0 halfway between
  float shake = sin(TWO_PI * 2 * b);      // twice per beat, for twitchy claws
  int m = move == 0 ? 1 + (n / 8) % 5 : move;

  switch (m) {
  case 1:   // shamble: stiff steps in place, one foot per beat, arms dangling and swinging
    float up = sin(PI * b);
    int side = n % 2 == 0 ? -1 : 1;
    t.bodyY = 14 * bob;
    t.squash = 1 - 0.025 * bob;
    t.lean = side * 0.035 * up;
    t.head = -0.1 * bob + side * 0.06 * up;
    t.backArm = 0.25 * s2;
    t.frontArm = -0.18 * s2;
    if (side < 0) {
      t.liftL = 40 * up;
      t.legL = 0.12 * up;
    } else {
      t.liftR = 40 * up;
      t.legR = 0.1 * up;
    }
    break;

  case 2:   // zombie reach: arms out in front, claws twitching, head lolling
    t.backArm = 0.75 + 0.07 * shake;
    t.frontArm = 0.4 - 0.06 * shake;
    t.lean = -0.04 + 0.03 * s2;
    t.head = -0.08 + 0.12 * s2;
    t.bodyY = 12 * bob;
    t.squash = 1 - 0.02 * bob;
    t.shiftX = -18 * s2;
    break;

  case 3:   // head bang: big nod on every beat, body pumps with it
    t.head = 0.08 - 0.3 * bob;
    t.lean = -0.07 * bob;
    t.bodyY = 22 * bob;
    t.squash = 1 - 0.035 * bob;
    t.backArm = 0.15 + 0.35 * bob;
    t.frontArm = 0.1 + 0.25 * bob;
    break;

  case 4:   // side shuffle: slide one way then the other, leaning into it, arms swinging together
    float slide = sin(PI * (two * 2 - 0.5));     // -1 .. 1, turns around every beat
    t.shiftX = 55 * slide;
    t.lean = -0.07 * slide;
    t.head = 0.08 * slide - 0.06 * bob;
    t.bodyY = 10 * bob;
    t.backArm = 0.3 + 0.3 * slide;
    t.frontArm = 0.15 + 0.25 * slide;
    t.legL = 0.08 * slide;
    t.legR = 0.08 * slide;
    t.liftL = slide > 0 ? 20 * bob : 0;
    t.liftR = slide < 0 ? 20 * bob : 0;
    break;

  case 5:   // hop every two beats, arms flying up
    float air = (two > 0.15 && two < 0.85) ? sin(PI * (two - 0.15) / 0.7) : 0;
    float crouch = max(0, 1 - min(two, 1 - two) / 0.15);
    t.hopY = -130 * air;
    t.bodyY = 26 * crouch;
    t.squash = 1 - 0.06 * crouch + 0.04 * air;
    t.head = 0.12 * air - 0.15 * crouch;
    t.backArm = 0.2 + 0.6 * air;
    t.frontArm = 0.1 + 0.35 * air;
    t.legL = 0.12 * air;
    t.legR = -0.06 * air;
    t.liftR = 15 * air;
    break;
  }
}

// ---------- turning around ----------

// Which way he should face right now: flips every few beats, on the beat.
// facing chases that quickly, so he squeezes thin and opens up the other way, like a 2D spin.
void updateFacing() {
  float want = flip ? -1 : 1;
  int every = TURN_EVERY[turnChoice];
  if (dancing && every > 0 && (beatCount() / every) % 2 == 1) want = -want;
  facing = lerp(facing, want, 0.3);
  if (abs(facing) < 0.02) facing = want * 0.02;   // never exactly 0 (an invisible zero-width frame)
}

// ---------- beat ----------

float beatMs()    { return 60000.0 / bpm; }
float beatPhase() { return ((millis() - beatOrigin) % beatMs()) / beatMs(); }
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

// ---------- keys ----------

void keyPressed() {
  if (key == 'c') {
    calibrating = !calibrating;
    ks.toggleCalibration();
  }
  if (key == 's') {
    ks.save(sketchPath("keystone.xml"));
    println("Saved corners");
  }
  if (key == 'p') thread("moveToTargetDisplay");   // re-snap the window onto the projector
  if (key == 't') tapTempo();
  if (key == '+' || key == '=') {
    bpm += 2;
    println("BPM: " + nf(bpm, 0, 1));
  }
  if (key == '-' || key == '_') {
    bpm = max(40, bpm - 2);
    println("BPM: " + nf(bpm, 0, 1));
  }
  if (key >= '0' && key <= '5') {
    move = key - '0';
    println("Move: " + MOVES[move]);
  }
  if (key == ' ') dancing = !dancing;
  if (key == 'k') party = !party;
  if (key == 'f') flip = !flip;
  if (key == 'r') {
    turnChoice = (turnChoice + 1) % TURN_EVERY.length;
    int e = TURN_EVERY[turnChoice];
    println(e == 0 ? "Turning: off" : "Turning around every " + e + (e == 1 ? " beat" : " beats"));
  }
  if (key == CODED) {
    if (keyCode == UP)   level = min(1, level + 0.05);
    if (keyCode == DOWN) level = max(0.1, level - 0.05);
  }
}
