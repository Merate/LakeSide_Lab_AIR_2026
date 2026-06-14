// ============================================================
// Threshold of Water
// Merate Barakat — LakeSideLab AIR Iowa, Lake Okoboji, June 2026
// ============================================================
//
// This sketch is the visual output of a two-week artist
// residency at Lakeside Lab AIR Iowa on Lake Okoboji. It was
// built in Processing (Java) over approximately 48 hours of
// intensive development and grew from a technical question
// into something I didn't plan.
//
// THE QUESTION:
// Can the fractal structure of natural soundscapes — the 1/f
// spectral signature that distinguishes living environments
// from machine-made noise — be made visible through the same
// mathematical language it inhabits?
//
// THE RECORDING:
// A Zoom H3-VR ambisonic microphone recorded 40 seconds at
// Lake Okoboji's shore — birds, water, wind. The file is
// saved in AmbiX B-format: four channels encoding sound as
// three-dimensional spatial information.
//   W = omnidirectional pressure (overall energy)
//   X = front-back axis
//   Y = left-right axis
//   Z = up-down axis
// These four channels become the data source for everything
// the sketch draws.
//
// THE FRACTAL CONNECTION:
// Processing's noiseDetail(4, 0.35) is not decoration.
// The falloff parameter maps directly to the spectral exponent
// β via: falloff = 2^(-β/2)
// β ≈ 1.5–1.7 is the pink noise / 1/f range that characterizes
// healthy natural soundscapes (Bernie Krause's biophony).
// Setting falloff = 0.35 makes the Perlin noise field
// mathematically equivalent to the fractal structure of
// the soundscape being analyzed. The visual field and the
// acoustic data speak the same mathematical language.
//
// THE ARCHITECTURE — three agents, two environments:
//
// ATTRACTOR — reads the AmbiX file, analyzes it using
// A-weighted FFT (IEC 61672 — matching human hearing), and
// writes acoustic influence values into a shared spatial array.
// It is the acoustic event made visible: a presence in the
// field that particles feel but cannot see.
//
// ALGEA AGENTS — 120 invisible swarm agents drifting
// downward from above the canvas toward the shore (bottom).
// They follow simplified boid rules: separation, weak cohesion,
// Perlin noise wander. What emerged — unprogrammed — was a
// natural accumulation line where the downward drift and
// upward shore resistance reach equilibrium. This is the
// shoreline. Sound events scatter them laterally; they
// reorient and reform. They age out and respawn at the top.
// Their presence shifts the particle field from blue to
// olive-green.
//
// PARTICLES — 40,000 points arranged in a 200×200 grid.
// Each reads two environmental signals: acoustic influence
// (from Attractor) and algae presence (from AlgeaAgent).
// In calm conditions they drift on a Perlin noise field —
// wind-biased, directional, glistening. When sound arrives,
// they ripple outward from the acoustic source with spring
// physics: repulsion, damping, return. Near the shore
// (bottom of canvas) they have stiffer springs and faster
// damping — shallow water behavior. In open water (top)
// they oscillate longer.
//
// WHAT I LEARNED:
// The emergent shoreline was never designed. The algae agents
// found it. The accumulation line at 80% of the canvas height
// exists because forces balanced — not because I told them
// to stop there. That is the thing about emergence: you build
// the conditions and something inhabits them.
//
// The question that organized the Silver Lake Fen visit —
// "who is recording whom" — is still open. The sentinel
// red-winged blackbirds watched us from the tops of the
// sedge grass. The microphone recorded them. This sketch
// makes their calls visible as disturbances in a field that
// was already moving. That feels approximately right.
//
// CONTROLS:
//   A — show/hide attractor position (red circle)
//   G — show/hide algae agent positions (green dots)
//   R — test recording (limited frames, audio loops)
//   C — cinematic recording (full audio sync, auto-stop)
//       Import frame sequence in Premiere at printed fps
// ============================================================

import javax.sound.sampled.*;
import java.io.RandomAccessFile;
import ddf.minim.*;
import ddf.minim.analysis.*;

// Legacy globals — kept for reference functions
float[] W, X, Y, Z;
int sampleRate;
int currentFrame = 0;
int bufferSize   = 512; // 10ms windows catch short bird chirp transients
FFT fftW, fftX, fftY, fftZ;

// Particle field — 200×200 = 40,000 points
int cols = 200;
int rows = 200;
ArrayList<Particle> grid = new ArrayList<Particle>();
float noiseTime = 0; // advances once per frame — never inside particle loop

// Patch class retained but inactive — functionally replaced by AlgeaAgent
int numPatches = 12;
ArrayList<Patch> patches = new ArrayList<Patch>();

// Recording
boolean recording  = false;
int frameCount_rec = 0;
int maxFrames      = 300;
String sessionFolder;

// Single Minim instance — passed to all Attractors
Minim minim;
ArrayList<Attractor> attractors = new ArrayList<Attractor>();

// Shared environment arrays — the medium through which agents communicate
// Cleared every frame. Agents write. Particles read.
float[] envAcoustic; // acoustic influence — drives particle ripple behavior
float[] envAlgae;    // algae presence — drives particle color shift

// Algae swarm — fixed population, age-based lifecycle
int numAlgae = 120;
ArrayList<AlgeaAgent> algaeAgents = new ArrayList<AlgeaAgent>();


void setup()
{
  size(1000, 1000);

  minim = new Minim(this);

  // One Attractor per microphone recording.
  // Add more here for multi-mic spatial work (Step 2).
  attractors.add(new Attractor(
    "260606_005_5_520_AmbiX.WAV",        // 4-channel AmbiX B-format
    "260606_005_5_520_Binaural_16bit.wav", // 16-bit binaural for playback
    minim
  ));

  loadGrid();

  envAcoustic = new float[cols * rows];
  envAlgae    = new float[cols * rows];

  loadAlgea();

  // THE FRACTAL PARAMETER:
  // noiseDetail(octaves, falloff) where falloff = 2^(-β/2)
  // β ≈ 1.5 (pink noise) → falloff ≈ 0.35
  // This is not aesthetic choice — it is the same mathematical
  // structure as the soundscape being visualized.
  noiseDetail(4, 0.35);

  sessionFolder = "output/" + year() + nf(month(), 2) + nf(day(), 2) +
                  "_" + nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2);
}


void draw()
{
  // Semi-transparent background creates motion trail
  // Alpha 200 = short persistence. background(0) = no trail.
  background(0, 0, 0, 200);

  // Environment reset — agents write fresh values each frame
  for (int i = 0; i < envAcoustic.length; i++) envAcoustic[i] = 0;
  for (int i = 0; i < envAlgae.length;    i++) envAlgae[i]    = 0;

  // Agent pipeline — order matters:
  // 1. Attractors write envAcoustic from audio analysis
  // 2. AlgeaAgents read envAcoustic, write envAlgae
  // 3. Particles read both, decide behavior, render
  for (Attractor a : attractors) a.run();
  runAlgae();
  for (Particle p : grid) p.run();

  noiseTime += 0.01;

  if (recording) record();
  stopCapture();
}


void keyPressed()
{
  if (key == 'p' || key == 'P')
    for (Patch p : patches) p.show = !p.show;

  if (key == 'a' || key == 'A')
    for (Attractor a : attractors) a.displayAttractor = !a.displayAttractor;

  if (key == 'g' || key == 'G')
    for (AlgeaAgent a : algaeAgents) a.show = !a.show;

  if (key == 'r' || key == 'R')
  {
    recording = !recording;
    frameCount_rec = 0;
    println(recording ? "Recording started" : "Recording stopped");
  }

  // Cinematic mode: rewinds audio, records full length,
  // prints fps for Premiere sequence import
  if (key == 'c' || key == 'C')
  {
    recording = true;
    frameCount_rec = 0;
    maxFrames = 999999;
    for (Attractor a : attractors) a.startSync();
    println("Cinematic recording started — synced to audio");
  }
}


void dispose()
{
  for (Attractor a : attractors) a.dispose();
  minim.stop();
}
