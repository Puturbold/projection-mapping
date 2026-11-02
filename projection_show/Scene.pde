// What every canvas in the show has: a size, its own drawing surface, its own Keystone corners,
// and an on/off switch.

abstract class Scene {
  String name;
  int W, H;
  PGraphics pg;
  CornerPinSurface surface;
  boolean visible = true;

  Scene(String name, int w, int h) {
    this.name = name;
    W = w;
    H = h;
  }

  void init() {
    surface = ks.createCornerPinSurface(W, H, 20);
    pg = createGraphics(W, H, P3D);
    setupScene();
  }

  abstract void setupScene();
  abstract void drawScene();   // draws one frame into pg (beginDraw / endDraw are done for you)
  void onKey() {}
}
