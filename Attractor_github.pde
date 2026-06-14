// ============================================================
// Attractor.pde — Threshold of Water
// Merate Barakat — LakeSideLab AIR Iowa, June 2026
// ============================================================
// The Attractor is the acoustic agent at the center of this work.
//
// It owns a 40-second AmbiX B-format field recording made on
// the shore of Lake Okoboji. Each frame it advances through
// the recording, analyzes a 10ms window of audio, and projects
// the result as a spatial influence field that 40,000 particles
// can sense and respond to.
//
// HOW IT ANALYZES SOUND:
// Rather than simple volume measurement, the Attractor uses
// A-weighting (IEC 61672 standard) — the same frequency
// correction used in professional sound level meters. This
// weights the spectrum to match human hearing: boosting
// 2–8kHz (where bird calls live) and suppressing low-frequency
// water rumble below 500Hz. The visualization responds to
// what we perceive, not just what is physically present.
//
// HOW IT FINDS DIRECTION:
// attractX is driven by A-weighted front-back energy.
// attractY is driven by the acoustic intensity vector W×Y —
// the product of omnidirectional pressure (W) and left-right
// channel (Y). This W×Y product is genuinely signed: positive
// when sound comes from one side, negative from the other.
// It is the standard ambisonics technique for direction-finding.
//
// HOW IT COMMUNICATES:
// The Attractor writes into envAcoustic[] — a flat float array
// with one cell per particle position. Influence falls off
// linearly from the attractor's screen position to its
// influenceRadius. Particles read their own cell's value
// and decide whether to drift or ripple. The Attractor never
// talks to particles directly. It changes the environment
// and particles sense it.
//
// SCALABILITY:
// One Attractor = one microphone.
// The architecture supports multiple Attractors writing
// additively into the same environment — a 4-mic cube array
// feeding a single particle field. That is the next step.
// ============================================================

class Attractor
{
  String filename;
  String playbackFile;

  // Own copies of decoded AmbiX channels — independent per attractor
  float[] W, X, Y, Z;
  int sampleRate  = 48000;
  int bufferSize  = 512;   // 10ms at 48kHz — short enough to catch bird chirps
  int currentFrame = 0;
  int lastMillis   = 0;

  FFT fftW, fftX, fftY, fftZ;

  Minim minim;
  AudioPlayer player;

  // Screen position and strength — computed each frame by analyze()
  // Read by Particle.run() to determine ripple direction
  float attractX;
  float attractY;
  float attractStrength;

  float influenceRadius = 200; // px — radius of acoustic influence zone

  // Smoothed strength — lerp toward raw value each frame.
  // Prevents single-frame chirp spikes from dominating.
  // smoothing=0.45 means 55% response to new values per frame.
  float smoothStrength = 0;
  float smoothing      = 0.45;

  float smoothX = 0;        // smoothed Y-axis position (intensity vector)
  boolean analysisStarted = false;
  boolean displayAttractor = false; // debug toggle — 'A' key


  Attractor(String _filename, String _playbackFile, Minim _minim)
  {
    filename     = _filename;
    playbackFile = _playbackFile;
    minim        = _minim;
    lastMillis   = millis();

    loadAmbiXLocal(filename);

    fftW = new FFT(bufferSize, sampleRate);
    fftX = new FFT(bufferSize, sampleRate);
    fftY = new FFT(bufferSize, sampleRate);
    fftZ = new FFT(bufferSize, sampleRate);

    player = minim.loadFile(playbackFile);
    player.loop();
  }


  void run()
  {
    advancePlayhead();
    analyze();
    writeEnvironment();
    if (displayAttractor) display();
  }


  // ANALYZE — the perceptual signal processing chain:
  // 1. Extract 10ms audio window from each spatial channel
  // 2. FFT: convert time-domain samples to frequency spectrum
  // 3. A-weight: apply perceptual frequency correction
  // 4. Power compress: boost quiet events so they register visually
  // 5. Map to screen position and influence strength
  void analyze()
  {
    if (currentFrame + bufferSize >= W.length) return;

    float[] wBuf = subset(W, currentFrame, bufferSize);
    float[] xBuf = subset(X, currentFrame, bufferSize);
    float[] yBuf = subset(Y, currentFrame, bufferSize);
    float[] zBuf = subset(Z, currentFrame, bufferSize);

    fftW.forward(wBuf);
    fftX.forward(xBuf);
    fftY.forward(yBuf);
    fftZ.forward(zBuf);

    // A-weighted perceptual energy per channel
    float wLevel = aWeightedLevel(fftW); // omni — overall loudness
    float xLevel = aWeightedLevel(fftY); // front-back energy → screen X
    float yLevel = aWeightedLevel(fftX); // left-right energy → screen Y

    // Power compression (exponent 0.6):
    // Without this, the occasional loud chirp dominates everything.
    // Raising to power < 1 compresses the dynamic range so quiet
    // sounds still produce visible ripples.
    float xCompressed = pow(map(xLevel, 0, 0.8, 0, 1), 0.6);
    float yCompressed = pow(map(yLevel, 0, 0.8, 0, 1), 0.6);

    // Horizontal position from A-weighted front-back energy
    attractX = width/2 + map(xCompressed, 0, 1, -width/2, width/2);
    attractX = constrain(attractX, 0, width);

    // Vertical position from acoustic intensity vector W×Y
    // W×Y product: omnidirectional × left-right = signed direction
    // Positive = sound from one side, negative = other side
    float wRMS = rms(wBuf);
    float yRMS = rms(yBuf);
    float lrDirection = 0;
    if (wRMS > 0.001) {
      for (int i = 0; i < wBuf.length; i++)
        lrDirection += wBuf[i] * yBuf[i];
      lrDirection /= wBuf.length;
      lrDirection /= (wRMS * yRMS + 0.0001); // normalize to -1..+1
    }
    float targetY = map(lrDirection, -1, 1, 0, height);
    smoothX  = lerp(smoothX, targetY, 0.15); // smooth position drift
    attractY = constrain(smoothX, 0, height);

    // Attractor strength — smoothed to give chirps time to produce visible displacement
    float rawStrength = pow(map(wLevel, 0, 0.8, 0, 1), 0.6);
    smoothStrength    = lerp(smoothStrength, rawStrength, 1 - smoothing);
    attractStrength   = smoothStrength;
  }


  // LEGACY ANALYZE — both axes driven by A-weighted energy only.
  // No signed direction. Swap analyze() call to revert.
  void analyzeLegacy()
  {
    if (currentFrame + bufferSize >= W.length) return;
    float[] wBuf = subset(W, currentFrame, bufferSize);
    float[] xBuf = subset(X, currentFrame, bufferSize);
    float[] yBuf = subset(Y, currentFrame, bufferSize);
    float[] zBuf = subset(Z, currentFrame, bufferSize);
    fftW.forward(wBuf); fftX.forward(xBuf);
    fftY.forward(yBuf); fftZ.forward(zBuf);
    float wLevel = aWeightedLevel(fftW);
    float xLevel = aWeightedLevel(fftY);
    float yLevel = aWeightedLevel(fftX);
    float xCompressed = pow(map(xLevel, 0, 0.8, 0, 1), 0.6);
    float yCompressed = pow(map(yLevel, 0, 0.8, 0, 1), 0.6);
    attractX = width/2  + map(xCompressed, 0, 1, -width/2, width/2);
    attractY = height/2 + map(yCompressed, 0, 1, -height/2, height/2);
    attractX = constrain(attractX, 0, width);
    attractY = constrain(attractY, 0, height);
    float rawStrength = pow(map(wLevel, 0, 0.8, 0, 1), 0.6);
    smoothStrength    = lerp(smoothStrength, rawStrength, 1 - smoothing);
    attractStrength   = smoothStrength;
  }


  // Write acoustic influence into shared environment array.
  // Linear falloff from attractor center to influenceRadius.
  // Multiple Attractors accumulate additively — cells near
  // several microphones receive higher combined influence.
  void writeEnvironment()
  {
    float cellW = width  / float(cols);
    float cellH = height / float(rows);
    int idx = 0;
    for (int i = 0; i < cols; i++) {
      for (int j = 0; j < rows; j++) {
        float px = i * cellW + cellW/2;
        float py = j * cellH + cellH/2;
        float d  = dist(px, py, attractX, attractY);
        float influence = 0;
        if (d < influenceRadius) {
          influence = map(d, 0, influenceRadius, attractStrength, 0);
          influence = constrain(influence, 0, 1);
        }
        envAcoustic[idx] = constrain(envAcoustic[idx] + influence, 0, 1);
        idx++;
      }
    }
  }


  // millis()-based real-time sync — frame-rate independent.
  // Keeps analysis aligned with Minim binaural playback.
  void advancePlayhead()
  {
    int elapsed  = millis() - lastMillis;
    lastMillis   = millis();
    currentFrame += (int)(sampleRate * elapsed / 1000.0);
    if (currentFrame + bufferSize >= W.length) currentFrame = 0;
  }


  // Cinematic recording sync — rewinds audio and analysis together.
  // Called by 'C' key in main sketch.
  void startSync()
  {
    player.rewind();
    player.play();
    currentFrame = 0;
    lastMillis   = millis();
    analysisStarted = true;
  }


  void display()
  {
    noFill();
    stroke(255, 80, 80, 150);
    ellipse(attractX, attractY, influenceRadius * 2, influenceRadius * 2);
    fill(255, 80, 80, 200);
    noStroke();
    ellipse(attractX, attractY, 8, 8);
  }


  void dispose() { player.close(); }


  // Manual 24-bit 4-channel WAV parser.
  // javax.sound.sampled cannot handle 24-bit audio — it returns
  // -1 for bit depth. RandomAccessFile reads raw bytes directly,
  // walks the WAV chunk structure to find audio data, then
  // deinterleaves 4 channels into W/X/Y/Z float arrays.
  void loadAmbiXLocal(String _filename) {
    try {
      File f = new File(sketchPath("data/" + _filename));
      RandomAccessFile raf = new RandomAccessFile(f, "r");
      int channels = 4; sampleRate = 48000;
      int bitDepth = 24; int bytesPerSample = bitDepth / 8;
      raf.seek(12); // skip RIFF/WAVE header
      byte[] buf4 = new byte[4]; byte[] chunkId = new byte[4];
      while (raf.getFilePointer() < raf.length() - 8) {
        raf.read(chunkId); raf.read(buf4);
        int chunkSize = (buf4[3]&0xFF)<<24|(buf4[2]&0xFF)<<16|(buf4[1]&0xFF)<<8|(buf4[0]&0xFF);
        if (new String(chunkId).equals("data")) {
          println(filename + " — data chunk at: " + raf.getFilePointer()); break;
        }
        raf.skipBytes(chunkSize);
      }
      long dataLength = raf.length() - raf.getFilePointer();
      byte[] rawBytes = new byte[(int)dataLength];
      raf.read(rawBytes);
      int totalFrames = rawBytes.length / (channels * bytesPerSample);
      println(filename + " — " + nf(totalFrames/(float)sampleRate,0,1) + " seconds");
      W = new float[totalFrames]; Y = new float[totalFrames];
      Z = new float[totalFrames]; X = new float[totalFrames];
      // Deinterleave: [W0][Y0][Z0][X0][W1][Y1][Z1][X1]...
      // 24-bit little-endian: third byte NOT masked — preserves sign bit
      for (int i = 0; i < totalFrames; i++) {
        for (int c = 0; c < channels; c++) {
          int idx = (i*channels+c)*bytesPerSample;
          int raw = (rawBytes[idx]&0xFF)|((rawBytes[idx+1]&0xFF)<<8)|((rawBytes[idx+2])<<16);
          float sample = raw / 8388608.0; // normalize 24-bit to -1..+1
          if (c==0) W[i]=sample; else if (c==1) Y[i]=sample;
          else if (c==2) Z[i]=sample; else if (c==3) X[i]=sample;
        }
      }
      println(filename + " loaded."); raf.close();
    } catch (Exception e) { println("Error: "+e.getMessage()); e.printStackTrace(); }
  }
}
