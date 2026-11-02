// Dancing Bear: your drawing as the head, with a hand drawn body that dances to the beat.

class BearScene extends Scene {
  float groundY = 770;

  // The drawing (in the data folder)
  PImage headLines, headFill;
  float headScale = 0.85;
  float headPivotX = 210;   // neck point in the drawing, in pixels
  float headPivotY = 300;

  // Body sizes
  float THIGH = 70, SHIN = 62;
  float UPPER = 80, FORE = 72;

  // Look
  boolean glow = true;
  boolean party = false;
  boolean wobble = true;
  float level = 1.0;
  color GLOW_LINE = color(255, 244, 225);
  color PAPER_BG = color(225, 215, 195);
  color PAPER_LINE = color(45, 38, 32);
  color[] PARTY = {
    color(255, 80, 140), color(80, 210, 255), color(255, 210, 60),
    color(170, 110, 255), color(80, 255, 150)
  };
  color lineCol, bgCol;
  float boil = 0;

  // Dance
  int move = 0;   // 0 = auto
  boolean dancing = true;
  String[] MOVES = {"auto", "bop", "raise the roof", "stomp", "sway", "jump"};
  BearPose pose = new BearPose();
  BearPose target = new BearPose();
  PVector hip = new PVector();

  // Torso outline, in torso coordinates (hips at 0,0, up is negative y)
  ArrayList<PVector> torsoLocal = new ArrayList<PVector>();

  // Head placement, updated every frame so the mane can line up with the drawing
  PVector headNeck = new PVector();
  float headAng = 0;

  // Fur strands. Torso: {x1, y1, x2, y2, bend} in torso coords.
  // Mane: {u across 0 = throat .. 1 = back, v down 0..1, lean, length, bend}.
  // Limbs: {t along the bone, side -1/1, outward lean, length scale, bend}.
  ArrayList<float[]> torsoFur = new ArrayList<float[]>();
  ArrayList<float[]> maneFur = new ArrayList<float[]>();
  ArrayList<float[]> limbFur = new ArrayList<float[]>();

  BearScene() {
    super("bear", 600, 800);
  }

  void setupScene() {
    headLines = loadImage("bear_head.png");
    headFill = loadImage("bear_head_fill.png");
    softenNeckFill();
    buildTorso();
  }

  void drawScene() {
    updateColors();
    boil = wobble ? floor(millis() / 110.0) * 0.37 : 0;   // redraws the lines ~9 times a second
    danceTargets();
    pose.lerpTo(target, 0.3);
    hip.set(W / 2.0 + pose.hipX, restHipY() + pose.hipY);
    updateHeadTransform();

    pg.hint(DISABLE_DEPTH_TEST);   // draw in painter's order
    pg.background(bgCol);

    drawFloor();
    drawLeg(tp(-48, -12), W / 2.0 - 50, pose.footLLift, 1);
    drawLeg(tp(48, -12), W / 2.0 + 56, pose.footRLift, 2);
    drawArm(tp(-76, -182), -1, pose.armLRaise, pose.armLBend, 3);   // back arm
    drawTorso();
    drawHead();
    drawArm(tp(68, -186), 1, pose.armRRaise, pose.armRBend, 4);     // front arm
  }

  float restHipY() {
    return groundY - 18 + 12 - 0.93 * (THIGH + SHIN);
  }

  // torso coordinates -> canvas, with lean and squash
  PVector tp(float lx, float ly) {
    float x = lx * (2 - pose.squash);
    float y = ly * pose.squash;
    float c = cos(pose.tilt);
    float s = sin(pose.tilt);
    return new PVector(hip.x + x * c - y * s, hip.y + x * s + y * c);
  }

  // ---------- dance moves ----------

  void danceTargets() {
    BearPose t = target;
    t.reset();

    if (!dancing) {
      t.hipY = 2 * sin(millis() * 0.002);
      t.headTilt = 0.03 * sin(millis() * 0.0013);
      t.armLRaise = 0.15;
      t.armRRaise = 0.15;
      return;
    }

    float b = beatPhase();
    int n = beatCount();
    float two = ((n % 2) + b) / 2.0;        // 0..1 across two beats
    float s2 = sin(TWO_PI * two);
    float bob = sq(cos(PI * b));            // 1 on the beat, 0 halfway between
    int m = move == 0 ? 1 + (n / 8) % 5 : move;

    switch (m) {
    case 1:   // bop
      t.hipY = 20 * bob;
      t.squash = 1 - 0.05 * bob;
      t.headTilt = -0.12 * bob;
      t.tilt = 0.05 * s2;
      t.armLRaise = 0.25 + 0.3 * s2;     // elbows in, fists up, pumping in turn
      t.armLBend = 1.9;
      t.armRRaise = 0.25 - 0.3 * s2;
      t.armRBend = 1.9;
      break;

    case 2:   // raise the roof
      t.hipY = 16 * bob;
      t.squash = 1 - 0.04 * bob;
      t.headTilt = -0.15 * bob;
      t.armLRaise = 2.3;
      t.armRRaise = 2.3;
      t.armLBend = 0.9 - 0.7 * bob;
      t.armRBend = 0.9 - 0.7 * bob;
      break;

    case 3:   // stomp: lift one foot per beat and lean away from it
      float up = sin(PI * b);
      int side = n % 2 == 0 ? -1 : 1;
      t.hipY = 10 * bob;
      t.tilt = -side * 0.1 * up;
      t.hipX = -side * 12 * up;
      t.headTilt = side * 0.1 * up;
      if (side < 0) {
        t.footLLift = 30 * up;
        t.armLRaise = 0.3 + 1.6 * up;
      } else {
        t.footRLift = 30 * up;
        t.armRRaise = 0.3 + 1.6 * up;
      }
      t.armLBend = 0.5;
      t.armRBend = 0.5;
      break;

    case 4:   // sway with arms up
      t.tilt = 0.14 * s2;
      t.hipX = 22 * s2;
      t.hipY = 8 * bob;
      t.headTilt = 0.08 * s2;
      t.armLRaise = 2.6 + 0.35 * s2;
      t.armRRaise = 2.6 - 0.35 * s2;
      t.armLBend = 0.35;
      t.armRBend = 0.35;
      break;

    case 5:   // jump every two beats
      float air = (two > 0.15 && two < 0.85) ? sin(PI * (two - 0.15) / 0.7) : 0;
      float crouch = max(0, 1 - min(two, 1 - two) / 0.15);
      t.hipY = 26 * crouch - 85 * air;
      t.footLLift = 70 * air;
      t.footRLift = 70 * air;
      t.squash = 1 - 0.08 * crouch + 0.05 * air;
      t.headTilt = 0.1 * air - 0.1 * crouch;
      t.armLRaise = 0.4 + 2.0 * air;
      t.armRRaise = 0.4 + 2.0 * air;
      t.armLBend = 0.4;
      t.armRBend = 0.4;
      break;
    }
  }

  // ---------- body parts ----------
  //
  // The body is drawn to match the pencil style of bear_head.png: mostly clean outlines, with fur
  // drawn as small clusters of long, gently curved strands (like the neck fur in the drawing).
  // A neck/shoulder piece (the "mane") joins the drawing to the body: its top is tucked under the
  // drawing and follows the head as it tilts, its bottom sits on the torso.

  void updateHeadTransform() {
    headNeck = tp(-12, -212);
    headAng = pose.tilt + pose.headTilt;
  }

  // a point in bear_head.png pixels -> canvas, following the head as it moves and tilts
  PVector hpt(float x, float y) {
    float dx = (x - headPivotX) * headScale;
    float dy = (y - headPivotY) * headScale;
    float c = cos(headAng);
    float s = sin(headAng);
    return new PVector(headNeck.x + dx * c - dy * s, headNeck.y + dx * s + dy * c);
  }

  // Fades out the bottom of the head's fill so the neck fur in the drawing
  // overlaps the body fur instead of ending in a hard edge.
  void softenNeckFill() {
    headFill.loadPixels();
    for (int y = 0; y < headFill.height; y++) {
      float k = constrain(map(y, 305, 352, 1, 0), 0, 1);
      if (k >= 1) continue;
      for (int x = 0; x < headFill.width; x++) {
        int i = y * headFill.width + x;
        int c = headFill.pixels[i];
        int a = (int) ((c >>> 24) * k);
        headFill.pixels[i] = (a << 24) | (c & 0xFFFFFF);
      }
    }
    headFill.updatePixels();
  }

  void buildTorso() {
    randomSeed(7);

    // torso outline: an egg shape, slightly uneven like a hand drawn line
    int n = 60;
    for (int i = 0; i < n; i++) {
      float a = TWO_PI * i / n;
      float sa = sin(a);   // +1 at the bottom, -1 at the top
      float rx = lerp(90, 128, (sa + 1) / 2);
      float k = 1 + random(-0.02, 0.025);
      torsoLocal.add(new PVector(cos(a) * rx * k, -112 + sa * 118 * k));
    }

    // fur clusters along the sides of the torso, crossing the outline so the edge looks shaggy
    for (int i = 0; i < 16; i++) {
      float side = i % 2 == 0 ? 1 : -1;
      float a = random(-0.75, 1.25);                 // right side, upper back to lower hip
      if (side < 0) a = PI - a;                      // mirror onto the left side
      float rx = lerp(90, 128, (sin(a) + 1) / 2);
      float k = random(0.8, 0.95);
      float x = cos(a) * rx * k;
      float y = -112 + sin(a) * 118 * k;
      addCluster(torsoFur, x, y, side * random(0.25, 0.55), random(22, 32));
    }
    // a few along the bottom
    for (int i = 0; i < 4; i++) {
      float a = random(1.25, 1.9);
      addCluster(torsoFur, cos(a) * 118, -112 + sin(a) * 110, random(-0.2, 0.2), random(14, 22));
    }
    // chest, continuing the neck fur down from under the chin
    for (int i = 0; i < 5; i++) {
      addCluster(torsoFur, random(-55, 45), random(-150, -118), random(-0.2, 0.25), random(22, 32));
    }

    // mane fur, below where the drawing's fill ends
    for (int i = 0; i < 13; i++) {
      addManeCluster(random(0.05, 0.9), random(0.3, 0.85), random(-0.15, 0.35), random(24, 36));
    }
    // shaggy back edge, continuing the ragged fur at the back of the head
    for (int i = 0; i < 10; i++) {
      addManeCluster(random(0.86, 0.97), map(i, 0, 9, 0, 0.92), random(0.45, 0.75), random(22, 32));
    }
    // fur bridging the back of the head into the back
    for (int i = 0; i < 6; i++) {
      addManeCluster(random(0.55, 0.85), random(0, 0.3), random(0.2, 0.5), random(22, 32));
    }
    // a few strands hanging off the throat
    for (int i = 0; i < 4; i++) {
      addManeCluster(random(0.0, 0.06), random(0.4, 0.9), random(-0.35, -0.1), random(18, 26));
    }

    // limb fur template, reused for every arm and leg segment
    float[] ts = {0.25, 0.5, 0.75};
    for (float t : ts) {
      for (int side = -1; side <= 1; side += 2) {
        for (int j = 0; j < 2; j++) {
          limbFur.add(new float[] {t + j * 0.08 + random(-0.03, 0.03), side, random(0.45, 0.8),
                                   random(0.85, 1.15), random(-0.12, 0.12)});
        }
      }
    }
    randomSeed(millis());   // so the other scenes' randomness isn't fixed
  }

  void addManeCluster(float u, float v, float lean, float len) {
    int count = random(1) < 0.5 ? 2 : 3;
    for (int j = 0; j < count; j++) {
      maneFur.add(new float[] {u + j * 0.04, v + random(-0.03, 0.03), lean + random(-0.08, 0.08),
                               len * random(0.8, 1.1), random(-0.12, 0.12)});
    }
  }

  // 2 or 3 roughly parallel strands, the way fur is drawn on the head
  void addCluster(ArrayList<float[]> list, float x, float y, float lean, float len) {
    int count = random(1) < 0.5 ? 2 : 3;
    float dx = lean;
    float dy = 1;
    float m = sqrt(dx * dx + dy * dy);
    dx /= m;
    dy /= m;
    for (int j = 0; j < count; j++) {
      float ox = -dy * (j - (count - 1) / 2.0) * 6 + random(-1.5, 1.5);
      float oy = dx * (j - (count - 1) / 2.0) * 6 + random(-1.5, 1.5);
      float l = len * random(0.8, 1.1);
      float tilt = random(-0.12, 0.12);
      float ex = dx + tilt;
      list.add(new float[] {x + ox, y + oy, x + ox + ex * l, y + oy + dy * l, random(-0.12, 0.12)});
    }
  }

  void drawTorso() {
    ArrayList<PVector> pts = new ArrayList<PVector>();
    for (PVector p : torsoLocal) pts.add(tp(p.x, p.y));
    pencilPath(pts, true, true, 500);

    drawMane();

    ArrayList<PVector> belly = new ArrayList<PVector>();
    for (float a = -0.3; a <= PI + 0.3; a += 0.2) belly.add(tp(-16 + cos(a) * 60, -86 + sin(a) * 70));
    pencilPath(belly, false, false, 501);

    for (int i = 0; i < torsoFur.size(); i++) {
      float[] f = torsoFur.get(i);
      strand(tp(f[0], f[1]), tp(f[2], f[3]), f[4], 600 + i);
    }
  }

  // throat edge of the mane: from under the jaw (head coords) down to the chest (torso coords)
  PVector maneFront(float v) {
    return PVector.lerp(hpt(146, 300), tp(-102, -128), v);
  }

  // back edge of the mane: from the bottom of the back-of-head fur, bulging out into a
  // bear's shoulder hump, down to the back of the torso
  PVector maneBack(float v) {
    PVector a = hpt(342, 200);   // where the back-of-head fur fades out
    PVector c = hpt(350, 300);   // keeps going the way the back of the head points
    PVector b = tp(122, -130);
    float u = 1 - v;
    return new PVector(u * u * a.x + 2 * u * v * c.x + v * v * b.x,
                       u * u * a.y + 2 * u * v * c.y + v * v * b.y);
  }

  void drawMane() {
    int steps = 10;
    ArrayList<PVector> front = new ArrayList<PVector>();
    ArrayList<PVector> back = new ArrayList<PVector>();
    for (int i = 0; i <= steps; i++) {
      front.add(maneFront(i / (float) steps));
      back.add(maneBack(i / (float) steps));
    }

    // fill: covers the top of the torso outline so the body flows straight into the neck
    pg.noStroke();
    pg.fill(bgCol);
    pg.beginShape();
    for (PVector p : front) pg.vertex(p.x, p.y);
    PVector dip = tp(0, -118);
    pg.vertex(dip.x, dip.y);
    for (int i = steps; i >= 0; i--) pg.vertex(back.get(i).x, back.get(i).y);
    PVector nape = hpt(300, 196);  // covers the faded back of the neck
    pg.vertex(nape.x, nape.y);
    PVector top = hpt(240, 262);   // hidden under the drawing
    pg.vertex(top.x, top.y);
    pg.endShape(CLOSE);

    // only the outer edges get a line; the top is tucked under the drawing
    pencilPath(front, false, false, 520);
    pencilPath(back, false, false, 521);

    float lean0 = pose.tilt;
    for (int i = 0; i < maneFur.size(); i++) {
      float[] f = maneFur.get(i);
      float u = constrain(f[0], 0, 1);
      float v = constrain(f[1], 0, 1);
      PVector root = PVector.lerp(maneFront(v), maneBack(v), u);
      float ang = lean0 - f[2];   // lean toward the back (+x) as the fur flows down
      PVector dir = new PVector(-sin(ang), cos(ang));
      strand(root, PVector.add(root, dir.mult(f[3])), f[4], 700 + i);
    }
  }

  void drawHead() {
    float jx = 0, jy = 0;
    if (wobble) {
      jx = (noise(boil, 3) - 0.5) * 3;
      jy = (noise(boil, 9) - 0.5) * 3;
    }
    pg.pushMatrix();
    pg.translate(headNeck.x, headNeck.y);
    pg.rotate(headAng);
    pg.scale(headScale);
    pg.imageMode(CORNER);
    pg.tint(bgCol);                                   // hides the body behind the head
    pg.image(headFill, -headPivotX, -headPivotY);
    pg.tint(lineCol);                                 // your pencil lines
    pg.image(headLines, -headPivotX + jx, -headPivotY + jy);
    pg.noTint();
    pg.popMatrix();
  }

  // side: -1 = arm on the left of the canvas, 1 = right. raise lifts the arm outward, bend bends the elbow.
  void drawArm(PVector sh, float side, float raise, float bend, int id) {
    float a1 = -side * raise + pose.tilt;
    PVector elbow = new PVector(sh.x - sin(a1) * UPPER, sh.y + cos(a1) * UPPER);
    float a2 = a1 - side * bend;
    PVector wrist = new PVector(elbow.x - sin(a2) * FORE, elbow.y + cos(a2) * FORE);

    // upper arm first, then the forearm on top of it. Neither draws the rounded end where it
    // joins its parent, so the arm grows out of the body and the elbow bends without a circle.
    limbSegment(sh, elbow, 24, 19, id * 10 + 2, id * 100 + 40);       // upper arm
    limbSegment(elbow, wrist, 17, 24, id * 10 + 1, id * 100 + 10);    // forearm and paw

    PVector dir = new PVector(-sin(a2), cos(a2));
    PVector perp = new PVector(-dir.y, dir.x);
    for (int k = -1; k <= 1; k++) {   // claws
      PVector p1 = PVector.add(wrist, PVector.mult(dir, 13)).add(PVector.mult(perp, k * 9));
      PVector p2 = PVector.add(wrist, PVector.mult(dir, 25)).add(PVector.mult(perp, k * 10));
      strand(p1, p2, 0, id * 10 + 5 + k);
    }
  }

  void drawLeg(PVector root, float footX, float lift, int id) {
    PVector ankle = new PVector(footX, groundY - 18 - lift);
    PVector knee = ik(root, ankle, THIGH, SHIN);
    ankle = PVector.add(knee, PVector.sub(ankle, knee).setMag(SHIN));

    // foot points left, the way he faces
    PVector heel = new PVector(ankle.x + 8, ankle.y + 4);
    PVector toe = new PVector(ankle.x - 38, ankle.y + 6);
    pencilPath(capsule(heel, toe, 16, 15), true, true, id * 10 + 1);
    limbSegment(root, knee, 31, 26, id * 10 + 3, id * 100 + 40);      // thigh (top is under the torso)
    limbSegment(knee, ankle, 25, 21, id * 10 + 2, id * 100 + 10);     // shin, on top of thigh and foot

    for (int k = -1; k <= 1; k++) {   // toe claws
      PVector c1 = new PVector(toe.x - 8, toe.y + k * 5);
      PVector c2 = new PVector(toe.x - 18, toe.y + 2 + k * 6);
      strand(c1, c2, 0, id * 10 + 7 + k);
    }
  }

  // One limb segment from a (joint with the parent) to b. Filled, outlined on the sides and
  // the far end only, then furred.
  void limbSegment(PVector a, PVector b, float ra, float rb, int id, int furId) {
    ArrayList<PVector> c = capsule(a, b, ra, rb);
    pg.noStroke();
    pg.fill(bgCol);
    pg.beginShape();
    for (PVector p : c) pg.vertex(p.x, p.y);
    pg.endShape(CLOSE);

    // capsule() returns the arc around b first, then the arc around a; skip the arc around a
    int half = c.size() / 2;
    ArrayList<PVector> open = new ArrayList<PVector>();
    open.add(c.get(c.size() - 1));
    for (int i = 0; i < half; i++) open.add(c.get(i));
    open.add(c.get(half));
    pencilPath(open, false, false, id);

    drawLimbFur(a, b, ra, rb, furId);
  }

  // Fur strands along a limb segment (a -> b). They start inside the outline and run toward
  // the paw, angled outward so they poke past the edge and make the silhouette look furry.
  void drawLimbFur(PVector a, PVector b, float ra, float rb, int baseId) {
    PVector dir = PVector.sub(b, a);
    float boneLen = dir.mag();
    if (boneLen < 1) return;
    dir.div(boneLen);
    PVector perp = new PVector(-dir.y, dir.x);

    for (int i = 0; i < limbFur.size(); i++) {
      float[] f = limbFur.get(i);
      float t = constrain(f[0], 0.05, 0.95);
      float side = f[1];
      float r = lerp(ra, rb, t);
      PVector root = PVector.lerp(a, b, t).add(PVector.mult(perp, side * r * 0.6));
      PVector d = PVector.add(dir, PVector.mult(perp, side * f[2])).add(0, 0.2).normalize();
      float len = r * 0.95 * f[3];
      strand(root, PVector.add(root, d.mult(len)), f[4], baseId + i);
    }
  }

  void drawFloor() {
    ArrayList<PVector> line = new ArrayList<PVector>();
    line.add(new PVector(W / 2.0 - 190, groundY));
    line.add(new PVector(W / 2.0 + 190, groundY + 3));
    pencilPath(line, false, false, 900);
  }

  // two bone IK: knee position so the foot reaches the target, knee bending forward (left)
  PVector ik(PVector a, PVector t, float l1, float l2) {
    float d = constrain(PVector.dist(a, t), abs(l1 - l2) + 0.1, l1 + l2 - 0.1);
    float base = atan2(t.y - a.y, t.x - a.x);
    float alpha = acos(constrain((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d), -1, 1));
    float ang = base + alpha;
    return new PVector(a.x + cos(ang) * l1, a.y + sin(ang) * l1);
  }

  // rounded limb outline between two points
  ArrayList<PVector> capsule(PVector a, PVector b, float ra, float rb) {
    ArrayList<PVector> pts = new ArrayList<PVector>();
    float ang = atan2(b.y - a.y, b.x - a.x);
    int seg = 9;
    for (int i = 0; i <= seg; i++) {
      float t = ang - HALF_PI + PI * i / seg;
      float r = rb * (i % 2 == 0 ? 1 : 0.94);
      pts.add(new PVector(b.x + cos(t) * r, b.y + sin(t) * r));
    }
    for (int i = 0; i <= seg; i++) {
      float t = ang + HALF_PI + PI * i / seg;
      float r = ra * (i % 2 == 0 ? 1 : 0.94);
      pts.add(new PVector(a.x + cos(t) * r, a.y + sin(t) * r));
    }
    return pts;
  }

  // ---------- hand drawn lines ----------

  void pencilPath(ArrayList<PVector> raw, boolean closed, boolean filled, int id) {
    if (filled) {
      pg.noStroke();
      pg.fill(bgCol);
      pg.beginShape();
      for (PVector p : raw) pg.vertex(p.x, p.y);
      pg.endShape(CLOSE);
    }

    ArrayList<PVector> pts = densify(raw, closed, 14);
    pg.noFill();
    for (int pass = 0; pass < 2; pass++) {
      pg.stroke(lineCol, pass == 0 ? 235 : 120);
      pg.strokeWeight(pass == 0 ? 2.6 : 1.3);
      float jit = pass == 0 ? 3 : 6;
      pg.beginShape();
      for (int i = 0; i < pts.size(); i++) {
        PVector p = pts.get(i);
        float nx = noise(id * 3.7 + pass * 11.1, i * 0.45, boil) - 0.5;
        float ny = noise(id * 5.3 + pass * 7.7 + 50, i * 0.45, boil) - 0.5;
        pg.vertex(p.x + nx * jit, p.y + ny * jit);
      }
      if (closed) pg.endShape(CLOSE);
      else pg.endShape();
    }
  }

  // one fur strand: a gently curved pencil line from a to b. bend curves it sideways.
  void strand(PVector a, PVector b, float bend, int id) {
    PVector d = PVector.sub(b, a);
    PVector side = new PVector(-d.y, d.x).mult(bend);
    pg.noFill();
    for (int pass = 0; pass < 2; pass++) {
      float j = pass == 0 ? 2.5 : 4.5;
      pg.stroke(lineCol, pass == 0 ? 225 : 90);
      pg.strokeWeight(pass == 0 ? 2.0 : 1.1);
      float s = id * 1.9 + pass * 17.3;
      pg.beginShape();
      for (int i = 0; i <= 4; i++) {
        float t = i / 4.0;
        float off = 4 * t * (1 - t);   // 0 at the ends, 1 in the middle
        float x = a.x + d.x * t + side.x * off;
        float y = a.y + d.y * t + side.y * off;
        pg.vertex(x + (noise(s, i * 0.6, boil) - 0.5) * j, y + (noise(s + 40, i * 0.6, boil) - 0.5) * j);
      }
      pg.endShape();
    }
  }

  // adds points along long edges so the wobble bends them
  ArrayList<PVector> densify(ArrayList<PVector> pts, boolean closed, float step) {
    ArrayList<PVector> out = new ArrayList<PVector>();
    int n = pts.size();
    int last = closed ? n : n - 1;
    for (int i = 0; i < last; i++) {
      PVector a = pts.get(i);
      PVector b = pts.get((i + 1) % n);
      int k = max(1, ceil(PVector.dist(a, b) / step));
      for (int j = 0; j < k; j++) out.add(PVector.lerp(a, b, j / (float) k));
    }
    if (!closed) out.add(pts.get(n - 1).copy());
    return out;
  }

  // ---------- colors ----------

  color scaleColor(color c, float k) {
    return color(red(c) * k, green(c) * k, blue(c) * k);
  }

  void updateColors() {
    color base = glow ? GLOW_LINE : PAPER_LINE;
    if (party) base = PARTY[beatCount() % PARTY.length];
    if (glow) {
      lineCol = scaleColor(base, level);
      bgCol = color(0);
    } else {
      lineCol = base;
      bgCol = scaleColor(PAPER_BG, level);
    }
  }

  // ---------- keys ----------

  void onKey() {
    if (key >= '0' && key <= '5') {
      move = key - '0';
      println("Bear move: " + MOVES[move]);
    }
    if (key == ' ') dancing = !dancing;
    if (key == 'i') glow = !glow;
    if (key == 'k') party = !party;
    if (key == 'w') wobble = !wobble;
    if (key == CODED) {
      if (keyCode == UP)   level = min(1, level + 0.05);
      if (keyCode == DOWN) level = max(0.1, level - 0.05);
    }
  }
}

// ---------- bear pose ----------

class BearPose {
  float hipX, hipY, tilt, squash, headTilt;
  float armLRaise, armLBend, armRRaise, armRBend;
  float footLLift, footRLift;

  BearPose() {
    reset();
  }

  void reset() {
    hipX = 0;
    hipY = 0;
    tilt = 0;
    squash = 1;
    headTilt = 0;
    armLRaise = 0.2;
    armLBend = 0.3;
    armRRaise = 0.2;
    armRBend = 0.3;
    footLLift = 0;
    footRLift = 0;
  }

  void lerpTo(BearPose t, float k) {
    hipX = lerp(hipX, t.hipX, k);
    hipY = lerp(hipY, t.hipY, k);
    tilt = lerp(tilt, t.tilt, k);
    squash = lerp(squash, t.squash, k);
    headTilt = lerp(headTilt, t.headTilt, k);
    armLRaise = lerp(armLRaise, t.armLRaise, k);
    armLBend = lerp(armLBend, t.armLBend, k);
    armRRaise = lerp(armRRaise, t.armRRaise, k);
    armRBend = lerp(armRBend, t.armRBend, k);
    footLLift = lerp(footLLift, t.footLLift, k);
    footRLift = lerp(footRLift, t.footRLift, k);
  }
}
