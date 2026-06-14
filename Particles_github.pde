// ============================================================
// Particles.pde — Threshold of Water
// Merate Barakat — LakeSideLab AIR Iowa, June 2026
// ============================================================
// 40,000 points arranged in a 200×200 grid.
// Each is an autonomous agent that senses its local environment
// and decides its own behavior. No particle is told what to do.
//
// TWO STATES, ONE BLEND:
// Every particle reads its cell's value in envAcoustic[].
// Below 0.01 — pure drift. The field is calm.
// Above 0.15 — pure ripple. A sound event is here.
// Between — a proportional blend of both.
// This replaces the original boolean isDrift flag with a
// continuous gradient. The edge of a sound event is soft,
// not a hard boundary.
//
// DRIFT — the water surface at rest:
// Perlin noise displacement with two key properties:
//   1. Asymmetric coordinate scaling (X: 0.002, Y: 0.02)
//      creates directional wave bands rather than fog.
//      The 10x difference is what separates "shore" from "open water"
//      visually — parallel bands moving toward the bottom edge.
//   2. Wind bias: map(baseY, 0, height, 3.0, 0) means particles
//      near the top have stronger downward drift — wind coming
//      off the water surface.
//
// RIPPLE — acoustic response:
// Spring physics with two forces per frame:
//   Repulsion: pushes away from the attractor position.
//              Proportional to proximity — closest particles
//              get the strongest push.
//   Spring:    pulls back toward home (baseX, baseY).
//              Creates the return and oscillation.
// Velocity is damped each frame — energy bleeds away and
// particles eventually settle. How fast depends on where
// they are on the canvas.
//
// SHORE BIAS:
// damping and springK are set in the constructor based on baseY.
// Particles near the bottom (shore) have stiffer springs and
// faster damping — shallow water, quick settling.
// Particles near the top (open water) oscillate longer,
// travel further, return slowly.
// This is the spatial heterogeneity of a real shoreline
// encoded as physics parameters.
//
// COLOR — two hue families, same fractal luminosity:
// The glisten value (noise-driven brightness) is applied to
// both the blue-white (open water) and olive-green (algae)
// palettes. The same Perlin noise that moves the particles
// also drives their glistening — they brighten when displaced
// in the "lit" direction and darken when receding. The fractal
// structure of the noise is visible in the light.
// ============================================================

class Particle {

  float x, y;
  float baseX, baseY;
  float sz;
  color col;
  int gridIndex;

  float vx, vy;
  float damping;    // set in constructor — varies with shore position
  float springK;    // set in constructor — varies with shore position
  float repulseStr = 12.0;


  Particle(float _x, float _y, int _index)
  {
    x = _x; y = _y;
    baseX = _x; baseY = _y;
    sz = 2;
    col = color(255, 200);
    gridIndex = _index;
    vx = 0; vy = 0;

    // Shore bias — physics varies with vertical position.
    // Top (y=0) = deep open water: soft spring, slow decay.
    // Bottom (y=height) = shallow shore: stiff spring, fast decay.
    damping = map(baseY, 0, height, 0.94, 0.78);
    springK = map(baseY, 0, height, 0.04, 0.18);
  }


  void run()
  {
    float influence = envAcoustic[gridIndex];

    if (influence < 0.01) {
      drift();
    } else if (influence > 0.15) {
      Attractor a = attractors.get(0);
      ripple(a.attractX, a.attractY, a.attractStrength);
    } else {
      // Blend zone — compute both, lerp proportionally
      drift();
      float driftX = x, driftY = y, driftSz = sz;
      color driftCol = col;
      Attractor a = attractors.get(0);
      ripple(a.attractX, a.attractY, a.attractStrength);
      float t = map(influence, 0.01, 0.15, 0, 1);
      x   = lerp(driftX, x, t);
      y   = lerp(driftY, y, t);
      sz  = lerp(driftSz, sz, t);
      col = lerpColor(driftCol, col, t);
    }

    display();
  }


  void ripple(float _attractX, float _attractY, float _attractStrength)
  {
    float springX = (baseX - x) * springK;
    float springY = (baseY - y) * springK;

    float dx = x - _attractX;
    float dy = y - _attractY;
    float d  = dist(x, y, _attractX, _attractY);

    float repulse = 0;
    if (d > 0 && d < 200)
      repulse = map(d, 0, 200, _attractStrength * repulseStr, 0);

    float nx = (d > 0) ? dx / d : 0;
    float ny = (d > 0) ? dy / d : 0;

    vx += springX + nx * repulse;
    vy += springY + ny * repulse;
    vx *= damping;
    vy *= damping;

    x += vx;
    y += vy;

    float displacement = dist(x, y, baseX, baseY);
    sz = map(displacement, 0, 50, 2, 8);
  }


  void drift()
  {
    float noiseMin     = -12;
    float noiseMax     =  12;
    float windStrength =  3.0;

    // Wind gradient — stronger at top of canvas
    float windBias = map(baseY, 0, height, windStrength, 0);

    // Asymmetric scaling creates directional wave bands not fog
    float noiseX = map(noise(baseX * 0.002 + 100, baseY * 0.002, noiseTime),
                       0, 1, noiseMin, noiseMax);
    float noiseY = map(noise(baseX * 0.002, baseY * 0.02, noiseTime + 100),
                       0, 1, noiseMin, noiseMax) + windBias;

    x = baseX + noiseX;
    y = baseY + noiseY;

    // Glisten: combined displacement direction drives brightness
    float glisten = constrain(map(noiseX + noiseY, noiseMin, noiseMax, 0, 1), 0, 1);
    sz = map(glisten, 0, 1, 3, 2);

    colorAlgea(glisten);
  }


  // Blue-white (open water) ↔ olive-green (algae) color system.
  // Same glisten noise drives brightness in both hue families —
  // the fractal luminosity pattern is consistent across the field.
  void colorAlgea(float _glisten)
  {
    color blueCol  = lerpColor(color(20, 40, 120, 100),
                               color(200, 230, 255, 220), _glisten);
    color oliveCol = lerpColor(color(10, 25, 8, 100),
                               color(180, 220, 100, 220), _glisten);

    float greenInfluence = constrain(envAlgae[gridIndex], 0, 1);

    color algaeCol = lerpColor(color(10, 35, 8, 100),
                               color(160, 200, 80, 220), greenInfluence);
    color baseCol  = lerpColor(blueCol, oliveCol, greenInfluence);
    col = lerpColor(baseCol, algaeCol, greenInfluence);
  }


  void display() {
    noStroke();
    fill(col);
    ellipse(x, y, sz, sz);
  }
}
