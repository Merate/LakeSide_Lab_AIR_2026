# Threshold of Water

**Merate A. Barakat** — Associate Professor, College of Design, Iowa State University  
LakeSideLab Artist-in-Residency, Lake Okoboji, Iowa — June 2026

---

## What this is

*Threshold of Water* is a generative visual artwork built in Processing (Java) during a two-week artist residency on the shore of Lake Okoboji. It visualizes a 40-second AmbiX B-format ambisonic field recording made at the water's edge — birds, wind, water — as a living particle field of 40,000 points.

The piece asks a question that emerged from a kinship writing workshop at Silver Lake Fen: **who is recording whom?**

---

## The research question

My research sits at the intersection of soundscape ecology, fractal acoustics, and computational design. The core question: can the fractal structure of natural soundscapes — the 1/f spectral signature that distinguishes living environments from machine-made noise — be made *visible* through the same mathematical language it inhabits?

Natural soundscapes exhibit what is known as **1/f noise** (pink noise): acoustic energy that falls off inversely with frequency across scales. This self-similar structure, characterized by a spectral exponent β ≈ 1.5–1.7, is the measurable signature of biophony — the biological sound layer that Bernie Krause distinguishes from geophony (physical environment sounds) and anthrophony (human-made sounds). Research by Yang et al. (2015) and Jermyn et al. (2023) confirms this 1/f structure as a reliable biomarker of healthy natural soundscapes.

The fractal connection in this sketch is not metaphorical. Processing's `noiseDetail(octaves, falloff)` is a computational construction of fractal Brownian motion. The `falloff` parameter maps directly to the spectral exponent β:

```
falloff = 2^(-β/2)
```

Setting `noiseDetail(4, 0.35)` produces Perlin noise with β ≈ 1.5 — mathematically equivalent to the fractal structure of the soundscape being analyzed. **The visual field and the acoustic data speak the same mathematical language.**

---

## The field recording

Recorded with a Zoom H3-VR ambisonic microphone in AmbiX B-format — four channels encoding sound as three-dimensional spatial information:

- **W** — omnidirectional pressure (overall energy)
- **X** — front-back axis
- **Y** — left-right axis
- **Z** — up-down axis

The file is parsed manually in Processing using `RandomAccessFile` because Java's `javax.sound.sampled` cannot handle 24-bit multichannel WAV files. The four channels are decoded and held in memory as float arrays, then analyzed frame-by-frame using A-weighted FFT (IEC 61672 standard) — the same perceptual frequency weighting used in professional sound level meters, which boosts the 2–8kHz range where bird calls live and suppresses low-frequency water rumble.

---

## Architecture

Three agent types communicate through two shared environment arrays:

```
Attractor  →  reads AmbiX file  →  writes envAcoustic[]
AlgeaAgent →  reads envAcoustic[]  →  writes envAlgae[]
Particle   →  reads envAcoustic[] + envAlgae[]  →  visual output
```

Both environment arrays are cleared every frame. Agents write. Particles read. No agent talks to another directly.

### Attractor
The acoustic agent. Self-contained: owns its AmbiX file, FFT objects, and binaural playback. Each frame it advances through the recording, computes A-weighted energy per spatial channel, applies power compression to boost quiet events, and projects its influence as a spatial field that particles can sense. The influence falls off linearly from the attractor's screen position to its radius. Multiple Attractors would accumulate additively — one per microphone in a multi-mic array.

### AlgeaAgent (swarm)
120 invisible agents drifting downward from above the canvas toward the shore (bottom edge). They follow simplified boid rules: separation, weak cohesion, Perlin noise wander. What emerged — never explicitly programmed — was a natural accumulation line where downward drift and shore resistance reach equilibrium. This is the shoreline. Sound events scatter them laterally; they reorient and reform. They age out after 3000–6000 frames and respawn at the top. Their presence shifts the particle field from blue-white to olive-green.

**The emergent shoreline was the most important discovery of the residency.** I spent considerable time trying to "fix" it — thinking agents were failing to reach the bottom. Then I walked by the river and saw that algae does in fact stop a good distance from the shore and accumulates there. The emergent behavior was ecologically accurate.

### Particle field
40,000 points in a 200×200 grid. Each particle reads its cell's value in `envAcoustic[]` and blends between two behaviors:

- **drift()** — Perlin noise displacement with asymmetric coordinate scaling (X: 0.002, Y: 0.02) creates directional wave bands. Wind bias increases toward the top of the canvas. The `noiseDetail(4, 0.35)` setting directly encodes the 1/f fractal structure of the soundscape.
- **ripple()** — spring physics with repulsion from the acoustic attractor and return toward home position. Damping and spring stiffness vary with vertical position (shore bias): particles near the shore snap back faster, particles in open water oscillate longer.

Color shifts between blue-white (open water) and olive-green (algae presence) based on `envAlgae[]`. The same Perlin noise driving displacement also drives glistening — the fractal luminosity pattern is visible in the light.

---

## What I learned

The piece grew from a technical investigation into something I did not plan. Three days in the kinship writing workshop taught me that field recording is not neutral documentation. Listening is relational. The question "who is recording whom?" reframed everything: the sentinel red-winged blackbirds watching from the tops of the sedge grass were not just subjects to be recorded. Their calls, made visible here as disturbances in a field that was already moving, suggest something about observation, presence, and the permeability of thresholds.

---

## Requirements

- Processing 4.x — [processing.org](https://processing.org)
- Minim library — install via Processing's Library Manager (Sketch → Import Library → Manage Libraries → search "Minim")
- An AmbiX B-format 4-channel 24-bit WAV file
- A 16-bit stereo or binaural WAV file for playback (same recording, exported from Zoom Ambisonic Player or Audacity)

---

## Setup

1. Clone or download this repository
2. Place your audio files in the `data/` folder inside the sketch folder
3. Update the filenames in `setup()` in the main sketch:
```java
attractors.add(new Attractor(
  "your_ambix_file.WAV",
  "your_binaural_file.wav",
  minim
));
```
4. Run the sketch in Processing

---

## Controls

| Key | Action |
|-----|--------|
| `A` | Toggle attractor debug circle (shows acoustic position) |
| `G` | Toggle algae agent debug dots (shows swarm positions) |
| `R` | Start/stop test recording (limited frames, audio loops) |
| `C` | Cinematic recording — rewinds audio, records full length, auto-stops, prints fps for video editor sync |

---

## Recording output

Frames are saved to `output/YYYYMMDD_HHMMSS/` inside the sketch folder. For cinematic mode (`C` key), import the frame sequence into Premiere or DaVinci Resolve as an image sequence and set the frame rate to the value printed in the Processing console. This syncs the visual output with the original audio recording.

---

## Licenses

- **Code** — [GNU General Public License v3.0](LICENSE)
- **Field recordings, writing, images** — [Creative Commons Attribution-NonCommercial-ShareAlike 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)

The GPL v3 was chosen deliberately. The open source community built the tools this work depends on. Derivatives must remain open.

---

## References

- Krause, B. (1993). The niche hypothesis. *Soundscape Newsletter, 6*, 6–10.
- Yang, W., & Kang, J. (2013). Psychoacoustical evaluation of natural and urban sounds. *Journal of the Acoustical Society of America, 134*(1), 840–851.
- Yang, W., Kang, J., & Jian, K. (2015). 1/f noise in natural soundscapes. *Journal of the Acoustical Society of America, 138*(3).
- Jermyn, I., et al. (2023). 1/f structure in natural soundscapes. [Consensus](https://consensus.app/papers/details/18b54af9ada85e429b7a032db73d7748/)
- Taylor, R. P. (2006). Reduction of physiological stress using fractal art and architecture. *Leonardo, 39*(3), 245–251.
- Meyer, J. H. F., Land, R., & Baillie, C. (Eds.). (2010). *Threshold concepts and transformational learning*. Sense Publishers.

---

## About

Merate A. Barakat is an architect, educator, and researcher at Iowa State University's College of Design. This work is part of a broader research program investigating fractal sound structure as a measurable signature of natural soundscapes and its translation into generative visual art, biomimicry design, and architectural applications.

[ORCID](https://orcid.org/0000-0002-6347-9843) · [ISU College of Design](https://www.design.iastate.edu)

