// Listens to the song through the microphone and works out its tempo, so the show dances to the
// music without tapping.
//
// Needs the Sound library: Sketch > Import Library > Manage Libraries, search "Sound"
// (by The Processing Foundation) and install it. The first time it runs, macOS asks whether
// Processing may use the microphone: say yes.
//
// How it works: every frame it measures how much the sound just got louder across the spectrum,
// so drum hits and new notes show up as spikes. Once a second it looks back over the last
// 8 seconds for the spacing between spikes that repeats the most (that's the beat), then lines the
// beat up with the most recent hits. A new tempo has to show up three seconds in a row before
// the show switches to it, so a fill or a quiet patch doesn't throw it off.

import processing.sound.*;

AudioIn mic;
FFT fft;
Waveform waveform;      // the raw sound wave, for the wave canvas's line and square wave looks
boolean listening = true;
boolean micOk = false;

int LATENCY_MS = 60;   // the mic hears a beat a little late; [ and ] nudge this if the dancing looks off

int BANDS = 512;
float[] spectrum = new float[BANDS];
float[] prevLog = new float[BANDS];

// recent "sound just got louder" values, with the time each was measured
int HIST = 1200;   // about 20 seconds at 60 frames a second
float[] fluxV = new float[HIST];
int[] fluxT = new int[HIST];
int histHead = 0;
int histN = 0;

int nextEstimate = 0;
float pendingBpm = 0;
int pendingCount = 0;
int heardSomething = 0;     // last time a clear beat was heard
boolean warnedQuiet = false;

void startListening() {
  try {
    mic = new AudioIn(this, 0);
    mic.start();             // start, not play: play would send the mic back out the speakers
    fft = new FFT(this, BANDS);
    fft.input(mic);
    waveform = new Waveform(this, 1024);
    waveform.input(mic);
    micOk = true;
    println("Listening for the beat through the microphone (l turns it off, t taps instead)");
  }
  catch (Exception e) {
    println("Couldn't open the microphone: " + e.getMessage() + ". Tap the beat with t instead.");
    micOk = false;
    listening = false;
  }
}

// Called every frame from draw()
void listenForBeat() {
  if (!micOk) return;
  fft.analyze(spectrum);

  float flux = 0;
  for (int i = 1; i < BANDS; i++) {
    float lg = log(1 + 1000 * spectrum[i]);
    float rise = lg - prevLog[i];
    if (rise > 0) flux += i < 12 ? rise * 3 : rise;   // bass and kick drum count extra
    prevLog[i] = lg;
  }
  fluxV[histHead] = flux;
  fluxT[histHead] = millis();
  histHead = (histHead + 1) % HIST;
  histN = min(histN + 1, HIST);

  if (listening && millis() > nextEstimate) {
    nextEstimate = millis() + 1000;
    estimateTempo();
  }
}

void estimateTempo() {
  int now = millis();
  int RATE = 100;          // work at 100 samples a second (10 ms each)
  int N = 8 * RATE;        // over the last 8 seconds
  int oldest = (histHead - histN + HIST) % HIST;
  if (histN < 60 || now - fluxT[oldest] < 6000) return;   // need about 6 seconds of sound first

  // even 10 ms steps, oldest first
  float[] env = new float[N];
  int j = oldest;
  int used = 0;
  for (int k = 0; k < N; k++) {
    int t = now - (N - 1 - k) * 1000 / RATE;
    while (used < histN - 2 && fluxT[(j + 1) % HIST] <= t) {
      j = (j + 1) % HIST;
      used++;
    }
    int j2 = (j + 1) % HIST;
    int t1 = fluxT[j];
    int t2 = fluxT[j2];
    if (t < t1) env[k] = 0;
    else if (t2 <= t1 || t >= t2) env[k] = fluxV[j];
    else env[k] = lerp(fluxV[j], fluxV[j2], (t - t1) / (float) (t2 - t1));
  }

  // keep only the spikes: subtract the local average (about a third of a second)
  float[] e = new float[N];
  int half = 15;
  for (int k = 0; k < N; k++) {
    float sum = 0;
    int cnt = 0;
    for (int d = -half; d <= half; d++) {
      int kk = k + d;
      if (kk >= 0 && kk < N) {
        sum += env[kk];
        cnt++;
      }
    }
    e[k] = max(0, env[k] - sum / cnt);
  }

  // how well the spikes line up with themselves shifted by each possible beat length
  int minLag = floor(60.0 * RATE / 185);   // fastest: 185 BPM
  int maxLag = ceil(60.0 * RATE / 65);     // slowest: 65 BPM
  float[] ac = new float[2 * maxLag + 2];
  float ac0 = 0;
  for (int k = 0; k < N; k++) ac0 += e[k] * e[k];
  ac0 /= N;
  if (ac0 <= 0) return;
  for (int lag = minLag; lag < ac.length; lag++) {
    float s = 0;
    for (int k = lag; k < N; k++) s += e[k] * e[k - lag];
    ac[lag] = s / (N - lag);
  }

  // score each beat length, also counting the beat after it (helps pick the real beat over half of it),
  // with a gentle preference for tempos near 120
  float bestScore = 0;
  int bestLag = -1;
  float[] score = new float[maxLag + 2];
  for (int lag = minLag; lag <= maxLag; lag++) {
    float tempo = 60.0 * RATE / lag;
    float oct = log(tempo / 120.0) / log(2);
    float prior = exp(-0.5 * sq(oct / 0.9));
    score[lag] = (ac[lag] + 0.5 * ac[2 * lag]) * prior;
    if (score[lag] > bestScore) {
      bestScore = score[lag];
      bestLag = lag;
    }
  }
  if (bestLag < 0) return;

  float confidence = ac[bestLag] / ac0;   // about 0.05 for noise, 0.2 to 0.6 for music with a beat
  if (confidence < 0.12) {
    if (!warnedQuiet && now - heardSomething > 15000) {
      println("Not hearing a clear beat. Is music playing? If it is, check System Settings > " +
              "Privacy & Security > Microphone and allow Processing.");
      warnedQuiet = true;
    }
    return;
  }
  heardSomething = now;
  warnedQuiet = false;

  // fine tune between the neighboring beat lengths
  float lagF = bestLag;
  if (bestLag > minLag && bestLag < maxLag) {
    float a = score[bestLag - 1], b = score[bestLag], c = score[bestLag + 1];
    float den = a - 2 * b + c;
    if (den != 0) lagF += constrain(0.5 * (a - c) / den, -0.5, 0.5);
  }
  float est = 60.0 * RATE / lagF;

  // switch tempo only when the new one holds steady
  float ratio = est / bpm;
  if (abs(ratio - 1) < 0.04) {
    setTempo(lerp(bpm, est, 0.3));          // same tempo, just refine it
    pendingCount = 0;
  } else if (abs(ratio - 2) < 0.08 || abs(ratio - 0.5) < 0.04) {
    // double or half the current tempo: same song, keep dancing at the current speed
  } else if (pendingBpm > 0 && abs(est / pendingBpm - 1) < 0.04) {
    pendingCount++;
    pendingBpm = est;
    if (pendingCount >= 3) {
      setTempo(est);
      println("Heard " + nf(est, 0, 1) + " BPM");
      pendingCount = 0;
    }
  } else {
    pendingBpm = est;
    pendingCount = 1;
  }

  alignBeat(e, RATE, N, now);
}

// Moves the beat so it lands on the hits: tries every offset within one beat and keeps the one
// that lands on the most spikes over the last 8 seconds.
void alignBeat(float[] e, int RATE, int N, int now) {
  float P = 60.0 * RATE / bpm;
  float best = -1;
  int bestPhi = 0;
  for (int phi = 0; phi < (int) P; phi++) {
    float s = 0;
    for (float pos = N - 1 - phi; pos >= 0; pos -= P) {
      int k = round(pos);
      float v = 0;
      for (int d = -2; d <= 2; d++) {   // allow a little timing slop
        int kk = k + d;
        if (kk >= 0 && kk < N) v = max(v, e[kk]);
      }
      s += v;
    }
    if (s > best) {
      best = s;
      bestPhi = phi;
    }
  }
  int lastBeat = now - bestPhi * 1000 / RATE - LATENCY_MS;

  // nudge halfway there each second, so the beat slides into place instead of jumping
  float ms = beatMs();
  float err = (lastBeat - beatOrigin) % ms;
  if (err > ms / 2) err -= ms;
  if (err < -ms / 2) err += ms;
  beatOrigin += round(err * 0.5);
}

// Changes the tempo without jumping to a different beat number
void setTempo(float newBpm) {
  int now = millis();
  float pos = (now - beatOrigin) / beatMs();
  bpm = newBpm;
  beatOrigin = now - round(pos * beatMs());
}
