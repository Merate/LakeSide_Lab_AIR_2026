// ============================================================
// Algea_Agents.pde — Threshold of Water
// Merate Barakat — LakeSideLab AIR Iowa, June 2026
// ============================================================
// 120 invisible swarm agents simulating algae drifting toward
// the shore of Lake Okoboji.
//
// THE EMERGENT SHORELINE:
// The most important thing about this class is something that
// was never programmed: the accumulation line at roughly 80%
// of the canvas height.
//
// Each agent drifts downward (wander), is weakly attracted to
// nearby agents (cohesion), and repelled from close neighbors
// (separation). Near the bottom 20% of the canvas a shore
// resistance force pushes back gently. Somewhere between these
// forces — wander pushing down, shore pushing up, separation
// preventing crowding — the agents find an equilibrium and
// accumulate into a band. That band is the shoreline.
//
// I spent time trying to "fix" this — thinking it was a bug
// that agents weren't reaching the bottom. Then I went for a
// walk by the river and saw that algae does in fact stop a
// good distance from the shore and just sits there, slowly
// accumulating. The emergent behavior was correct all along.
//
// THE LIFECYCLE:
// Agents don't die when they reach the shore. They die when
// they age out — after 3000–6000 frames (100–200 seconds).
// This keeps the population stable, allows the shoreline to
// persist, and creates continuous renewal: new agents spawning
// at the top, drifting through open water, finding the line,
// settling, aging, disappearing. The line is always the same
// line but never the same agents.
//
// THE ACOUSTIC DISRUPTION:
// When a sound event registers in envAcoustic[] at an agent's
// position, the agent receives a lateral kick — left-half
// agents kick right, right-half kick left. This creates a
// diverging scatter pattern that breaks the loose cohesion.
// The agents then reorient and reform. It is beautiful.
//
// ENVIRONMENT COMMUNICATION:
// Each agent writes its presence into envAlgae[] — the second
// shared environment array. Particles read this to shift their
// color from blue-white (open water) toward olive-green (algae).
// The agent never touches a particle directly. It changes
// the environment and the particles sense it.
// ============================================================

class AlgeaAgent
{
  PVector loc;
  PVector vel;
  PVector acc;

  float noiseOffset; // unique Perlin seed — each agent moves independently
  float noiseT;

  float lifespan;    // 1.0 = full, fades near shore — limits velocity
  float maxSpeed;
  float wanderAngle;

  boolean show = false; // debug dot — toggle with 'G'

  int age    = 0;
  int maxAge = (int)random(3000, 6000); // 100–200 seconds at ~30fps


  AlgeaAgent(PVector _loc)
  {
    loc         = _loc.copy();
    vel         = new PVector(random(-0.3, 0.3), random(0.2, 0.6));
    acc         = new PVector(0, 0);
    noiseOffset = random(10000);
    noiseT      = random(100);
    lifespan    = 1.0;
    maxSpeed    = random(0.3, 0.8);
    wanderAngle = HALF_PI;
  }


  void run()
  {
    applyForces();
    update();
    wrapX();
    writeEnvAlgae();
    if (show) display();
    age++;
  }


  void applyForces()
  {
    acc.set(0, 0);

    PVector wanderForce   = wander();
    PVector separateForce = separate();
    PVector cohereForce   = cohere();
    PVector shoreForce    = shoreEffect();
    PVector acousticForce = acoustic();

    // Force weights — tuned for emergent shoreline behavior.
    // Separation stronger than cohesion prevents tight clumping.
    // Shore resistance allows accumulation without full stop.
    acc.add(PVector.mult(wanderForce,   0.4));
    acc.add(PVector.mult(separateForce, 0.9));
    acc.add(PVector.mult(cohereForce,   0.075));
    acc.add(PVector.mult(shoreForce,    0.85));
    acc.add(PVector.mult(acousticForce, 1.2));
  }


  // Perlin noise steering biased downward.
  // Each agent has a unique noiseOffset — they move independently
  // despite sharing the same noise function.
  PVector wander()
  {
    noiseT += 0.005;
    float nx = map(noise(noiseOffset,       noiseT), 0, 1, -0.3, 0.3);
    float ny = map(noise(noiseOffset + 100, noiseT), 0, 1,  0.1, 0.6);
    return new PVector(nx, ny);
  }


  // Push away from agents within 30px.
  // Inverse distance weighting: closer = stronger push.
  PVector separate()
  {
    float separationRadius = 30;
    PVector steer = new PVector(0, 0);
    int count = 0;
    for (AlgeaAgent other : algaeAgents) {
      if (other == this) continue;
      float d = PVector.dist(loc, other.loc);
      if (d > 0 && d < separationRadius) {
        PVector diff = PVector.sub(loc, other.loc);
        diff.normalize(); diff.div(d);
        steer.add(diff); count++;
      }
    }
    if (count > 0) steer.div(count);
    return steer;
  }


  // Weak pull toward average position of nearby agents.
  // Creates loose clustering without tight flocking.
  PVector cohere()
  {
    float cohesionRadius = 70;
    PVector sum = new PVector(0, 0);
    int count = 0;
    for (AlgeaAgent other : algaeAgents) {
      if (other == this) continue;
      float d = PVector.dist(loc, other.loc);
      if (d > 0 && d < cohesionRadius) { sum.add(other.loc); count++; }
    }
    if (count > 0) {
      sum.div(count);
      PVector desired = PVector.sub(sum, loc);
      desired.normalize(); desired.mult(0.3);
      return desired;
    }
    return new PVector(0, 0);
  }


  // Shore resistance — bottom 20% of canvas.
  // Lifespan fades here, reducing max velocity.
  // Creates the conditions for emergent accumulation.
  PVector shoreEffect()
  {
    float shoreZone   = height * 0.2;
    float distToShore = height - loc.y;
    if (distToShore < shoreZone) {
      lifespan = constrain(map(distToShore, 0, shoreZone, 0.0, 1.0), 0, 1);
      float resistance = map(distToShore, 0, shoreZone, 0.4, 0);
      return new PVector(0, -resistance);
    }
    lifespan = 1.0;
    return new PVector(0, 0);
  }


  // Read acoustic influence from shared environment.
  // Sound event above threshold → lateral kick breaks cohesion.
  // Direction determined by agent's position relative to canvas center.
  PVector acoustic()
  {
    int col = constrain((int)map(loc.x, 0, width,  0, cols), 0, cols-1);
    int row = constrain((int)map(loc.y, 0, height, 0, rows), 0, rows-1);
    float acousticInfluence = envAcoustic[col * rows + row];
    if (acousticInfluence > 0.08) {
      float kickDir   = (loc.x < width/2) ? 1 : -1;
      float kickForce = map(acousticInfluence, 0.08, 0.5, 0.3, 1.5);
      return new PVector(kickDir * kickForce, -0.2);
    }
    return new PVector(0, 0);
  }


  void update()
  {
    vel.add(acc);
    vel.limit(max(maxSpeed * lifespan, 0.15)); // minimum ensures death-line crossing
    loc.add(vel);
  }


  void wrapX()
  {
    if (loc.x < 0)     loc.x = width;
    if (loc.x > width) loc.x = 0;
  }


  // Age-based death — position doesn't matter.
  // Allows natural shore accumulation without forced culling.
  boolean isDead() { return age >= maxAge; }


  // Project presence into envAlgae[] — only nearby cells.
  // Particles read this to shift color blue → olive-green.
  void writeEnvAlgae()
  {
    float influenceRadius = 55;
    float cellW = width / float(cols);
    float cellH = height / float(rows);
    int minCol = (int)constrain((loc.x - influenceRadius)/cellW, 0, cols-1);
    int maxCol = (int)constrain((loc.x + influenceRadius)/cellW, 0, cols-1);
    int minRow = (int)constrain((loc.y - influenceRadius)/cellH, 0, rows-1);
    int maxRow = (int)constrain((loc.y + influenceRadius)/cellH, 0, rows-1);
    for (int i = minCol; i <= maxCol; i++) {
      for (int j = minRow; j <= maxRow; j++) {
        float d = dist(i*cellW+cellW/2, j*cellH+cellH/2, loc.x, loc.y);
        if (d < influenceRadius) {
          float influence = constrain(map(d, 0, influenceRadius, lifespan, 0), 0, 1);
          int idx = i * rows + j;
          envAlgae[idx] = constrain(envAlgae[idx] + influence, 0, 1);
        }
      }
    }
  }


  void display()
  {
    noStroke();
    fill(80, 180, 60, map(lifespan, 0, 1, 0, 180));
    ellipse(loc.x, loc.y, 4, 4);
  }
}
