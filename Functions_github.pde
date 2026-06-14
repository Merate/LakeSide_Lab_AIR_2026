// ============================================================
// Functions.pde — Threshold of Water
// Merate Barakat — LakeSideLab AIR Iowa, June 2026
// ============================================================
// Utility functions shared across all sketch files.
//
// The two most conceptually significant functions here are
// aWeight() and aWeightedLevel() — together they implement
// the perceptual bridge between physical measurement and
// human experience of sound.
//
// A-weighting (IEC 61672) was developed to model how the
// human ear actually hears across the frequency spectrum.
// We are most sensitive around 3–4kHz — a range that
// encompasses speech, bird calls, and most biological
// vocalizations. We hear bass and very high frequencies
// poorly by comparison. A-weighted measurements match
// what we perceive as loud, not just what physically moves
// the most air.
//
// In this sketch, A-weighting means the visualization
// responds to the biophony — the biological sounds — more
// strongly than to geophony (wind, water movement) which
// tends toward lower frequencies. Bird calls at the shore
// create visible disturbances. Low rumble of waves does not.
// This is perceptually honest.
// ============================================================


// Auto-stop cinematic recording when audio track ends.
// Called every frame from draw(). Prints actual fps for
// Premiere sequence import — variable frame rate during
// saveFrame() means you cannot assume 30fps.
void stopCapture()
{
  if (recording && attractors.get(0).player.position() >=
      attractors.get(0).player.length() - 100) {
    recording = false;
    println("Cinematic complete — " + frameCount_rec + " frames");
    println("Use fps: " +
            nf(frameCount_rec / (attractors.get(0).player.length()/1000.0), 1, 2));
  }
}


// Manage algae swarm lifecycle.
// Iterates backwards so removal doesn't skip indices.
// Fixed population: one dies, one spawns at top.
void runAlgae()
{
  for (int i = algaeAgents.size() - 1; i >= 0; i--)
  {
    AlgeaAgent a = algaeAgents.get(i);
    a.run();
    if (a.isDead()) {
      algaeAgents.remove(i);
      algaeAgents.add(new AlgeaAgent(
        new PVector(random(width), random(-200, 0))
      ));
    }
  }
}


// Initialize algae swarm with staggered spawn positions.
// Spread across one canvas height above screen so agents
// enter the field progressively over the first few minutes.
void loadAlgea()
{
  for (int i = 0; i < numAlgae; i++)
    algaeAgents.add(new AlgeaAgent(
      new PVector(random(width), random(-height, 0))
    ));
}


// Debug utility — find lowest agent Y position.
float getLowestY()
{
  float maxY = 0;
  for (AlgeaAgent a : algaeAgents)
    if (a.loc.y > maxY) maxY = a.loc.y;
  return maxY;
}


// A-WEIGHTING — IEC 61672 standard frequency weighting.
// Models human ear sensitivity across the spectrum:
//   rolls off steeply below 500Hz
//   peaks at 3–4kHz (most sensitive range — bird calls live here)
//   rolls off above 10kHz
// Returns a weight multiplier for a given frequency in Hz.
float aWeight(float freq)
{
  float f2 = freq * freq;
  float f4 = f2 * f2;
  float numerator   = 148840000.0 * f4;
  float denominator = (f2 + 424.36) *
                      sqrt((f2 + 11599.29) * (f2 + 544496.41)) *
                      (f2 + 148840000.0);
  if (denominator == 0) return 0;
  return numerator / denominator;
}


// A-WEIGHTED LEVEL — perceptual energy from FFT spectrum.
// Sums all frequency bands weighted by the A-curve,
// normalizes by total weight. Result: perceptual loudness,
// not physical energy.
float aWeightedLevel(FFT fft)
{
  float sum = 0, weightSum = 0;
  for (int i = 1; i < fft.specSize(); i++) {
    float weight = aWeight(fft.indexToFreq(i));
    sum       += fft.getBand(i) * weight;
    weightSum += weight;
  }
  return (weightSum == 0) ? 0 : sum / weightSum;
}


// Frame capture to timestamped session folder.
// Note: saveFrame() slows rendering significantly.
// For smooth video use 'C' key (cinematic mode) or OBS.
void record()
{
  saveFrame(sessionFolder + "/frame-####.png");
  frameCount_rec++;
  if (frameCount_rec >= maxFrames) {
    recording = false;
    println("Recording complete — " + frameCount_rec + " frames");
  }
}


// Initialize particle grid.
// Loop order — outer=cols, inner=rows — must match
// Attractor.writeEnvironment() exactly or gridIndex
// to environment[] mapping breaks silently.
void loadGrid()
{
  float cellW = width  / float(cols);
  float cellH = height / float(rows);
  int index = 0;
  for (int i = 0; i < cols; i++) {
    for (int j = 0; j < rows; j++) {
      grid.add(new Particle(i*cellW+cellW/2, j*cellH+cellH/2, index));
      index++;
    }
  }
  println("Grid loaded: " + grid.size() + " particles");
}


void loadPatch() // inactive — Patch replaced by AlgeaAgent
{
  for (int i = 0; i < numPatches; i++) {
    Patch p = new Patch();
    p.y = random(height);
    patches.add(p);
  }
}


// Root Mean Square of float buffer.
// Used in Attractor for W×Y intensity vector normalization.
float rms(float[] buf) {
  float sum = 0;
  for (float s : buf) sum += s * s;
  return sqrt(sum / buf.length);
}


// ============================================================
// LEGACY — reference functions, not in active pipeline
// ============================================================

float[] sliceBufferAWeighting()
{
  float[] c = new float[4];
  float[] wB=subset(W,currentFrame,bufferSize), xB=subset(X,currentFrame,bufferSize);
  float[] yB=subset(Y,currentFrame,bufferSize), zB=subset(Z,currentFrame,bufferSize);
  fftW.forward(wB); fftX.forward(xB); fftY.forward(yB); fftZ.forward(zB);
  c[0]=aWeightedLevel(fftW); c[1]=aWeightedLevel(fftX);
  c[2]=aWeightedLevel(fftY); c[3]=aWeightedLevel(fftZ);
  return c;
}

float[] sliceBufferRMS()
{
  float[] c = new float[4];
  float[] wB=subset(W,currentFrame,bufferSize), xB=subset(X,currentFrame,bufferSize);
  float[] yB=subset(Y,currentFrame,bufferSize), zB=subset(Z,currentFrame,bufferSize);
  fftW.forward(wB); fftX.forward(xB); fftY.forward(yB); fftZ.forward(zB);
  c[0]=rms(wB); c[1]=rms(xB); c[2]=rms(yB); c[3]=rms(zB);
  return c;
}

void loadAmbiX(String filename) {
  try {
    File f = new File(sketchPath("data/" + filename));
    RandomAccessFile raf = new RandomAccessFile(f, "r");
    int channels=4; sampleRate=48000; int bytesPerSample=3;
    raf.seek(12);
    byte[] buf4=new byte[4]; byte[] chunkId=new byte[4];
    while (raf.getFilePointer() < raf.length()-8) {
      raf.read(chunkId); raf.read(buf4);
      int sz=(buf4[3]&0xFF)<<24|(buf4[2]&0xFF)<<16|(buf4[1]&0xFF)<<8|(buf4[0]&0xFF);
      if (new String(chunkId).equals("data")) break;
      raf.skipBytes(sz);
    }
    long dl=raf.length()-raf.getFilePointer();
    byte[] rb=new byte[(int)dl]; raf.read(rb);
    int tf=rb.length/(channels*bytesPerSample);
    W=new float[tf]; Y=new float[tf]; Z=new float[tf]; X=new float[tf];
    for (int i=0;i<tf;i++) for (int c=0;c<channels;c++) {
      int idx=(i*channels+c)*bytesPerSample;
      int raw=(rb[idx]&0xFF)|((rb[idx+1]&0xFF)<<8)|((rb[idx+2])<<16);
      float s=raw/8388608.0;
      if(c==0)W[i]=s; else if(c==1)Y[i]=s; else if(c==2)Z[i]=s; else X[i]=s;
    }
    raf.close();
  } catch(Exception e){println("Error: "+e.getMessage()); e.printStackTrace();}
}
