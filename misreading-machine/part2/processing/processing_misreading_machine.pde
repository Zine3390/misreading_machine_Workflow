/*
  The Misreading Machine: From Machine Vision to Data-Driven Spatial Fragments
  Processing / P3D animation for DFPI / Bartlett Part 2 final output.

  Put these files in this sketch's data folder if you want a portable sketch:
  - dataset_2_yolo_spatial_elements_clean.csv
  - dataset_4_spatial_matching_improved.csv
  - dataset_4_architecture_treatise_text.csv
  - Rhino2.obj
  - Camden_3.obj

  Note: Processing normally loads OBJ well, but FBX is not reliably supported.
  Convert C:/Users/16598/workshop_final/Camden_3.fbx to Camden_3.obj in Blender,
  then place Camden_3.obj in the data folder or in C:/Users/16598/workshop_final/.
*/

import java.io.File;
import java.io.BufferedReader;
import java.util.ArrayList;
import java.util.HashMap;

// -----------------------------
// Adjustable render parameters
// -----------------------------
int CANVAS_W = 1280;
int CANVAS_H = 720;
int FPS = 24;
int DURATION_SECONDS = 65;       // 65 sec at 24 fps = 1560 frames
int PARTICLE_COUNT = 2800;
float POINT_SIZE = 2.15;
float FLOW_SPEED = 1.0;
float CAMERA_SPEED = 0.075;
boolean EXPORT_FRAMES = true;    // set false for preview; true to save PNG frames

// -----------------------------
// Project paths
// -----------------------------
String PROJECT_DIR = "C:/Users/16598/workshop_final";
String EXTERNAL_ASSET_DIR = "E:/研究生阶段资料/第二学期/爬虫Python/codex_processing";
String OUTPUT_DIR = PROJECT_DIR + "/processing_output";

String YOLO_CSV = "dataset_2_yolo_spatial_elements_clean.csv";
String MATCH_CSV = "dataset_4_spatial_matching_improved.csv";
String TEXT_CSV = "dataset_4_architecture_treatise_text.csv";

String RHINO_MODEL_FILE = "Rhino2.obj";
String CAMDEN_MODEL_FILE = "Cam3.obj";
String CAMDEN_MODEL_FALLBACK_FILE = "Camden_3.obj";
String CAMDEN_FBX_SOURCE = "Camden_3.fbx"; // reference only; convert to OBJ first

// -----------------------------
// Scene state
// -----------------------------
int TOTAL_FRAMES;
ArrayList<DetectionRow> detections = new ArrayList<DetectionRow>();
HashMap<String, MatchStats> matchByElement = new HashMap<String, MatchStats>();
ArrayList<PVector> rhinoVertices = new ArrayList<PVector>();
ArrayList<PVector> rhinoTargets = new ArrayList<PVector>();
ArrayList<PVector> camdenVertices = new ArrayList<PVector>();
ArrayList<Particle> particles = new ArrayList<Particle>();
ArrayList<Block> fallbackBlocks = new ArrayList<Block>();

PShape rhinoShape;
PShape camdenShape;
PFont hudFont;
int[] palette;
float minArea = 1;
float maxArea = 1;
float textDensity = 1.0;
int textRowCount = 0;
boolean usingFallbackRhino = false;
boolean usingFallbackCamden = false;

void setup() {
  size(1280, 720, P3D);
  smooth(8);
  frameRate(FPS);
  pixelDensity(1);
  randomSeed(42);
  noiseSeed(42);

  TOTAL_FRAMES = FPS * DURATION_SECONDS;
  new File(OUTPUT_DIR).mkdirs();

  palette = new int[] {
    color(0, 218, 255),
    color(33, 118, 255),
    color(255, 122, 42),
    color(255, 210, 75),
    color(120, 246, 214),
    color(180, 220, 255)
  };

  hudFont = createFont("Consolas", 12, true);

  loadData();
  loadModelsAndGeometry();
  createParticles();

  println("Misreading Machine ready.");
  println("Frames: " + TOTAL_FRAMES + " at " + FPS + " fps");
  println("Rhino targets: " + rhinoTargets.size() + " | Camden source points: " + camdenVertices.size());
  println("Export frames: " + EXPORT_FRAMES + " -> " + OUTPUT_DIR);
}

void draw() {
  float t = constrain(frameCount / float(max(1, TOTAL_FRAMES - 1)), 0, 1);
  float stageCity = smoothStep(0.02, 0.30, t);
  float stageMorph = smoothStep(0.24, 0.58, t);
  float stageCourtyard = smoothStep(0.52, 0.96, t);

  background(2, 4, 10);
  setupCamera(t);

  ambientLight(12, 18, 26);
  directionalLight(45, 90, 120, -0.25, 0.55, -0.75);

  drawTextDrivenField(t, stageCity, stageMorph);
  drawCourtyardFrame(t, stageMorph, stageCourtyard);
  drawCamdenMemory(t, 1.0 - stageMorph);
  drawParticleField(t, stageMorph, stageCourtyard);
  drawMachineHalo(t, stageCourtyard);
  drawHud(t);

  if (EXPORT_FRAMES) {
    saveFrame(OUTPUT_DIR + "/frame_####.png");
    if (frameCount >= TOTAL_FRAMES) {
      println("Finished frame export. Use ffmpeg to encode:");
      println("ffmpeg -framerate " + FPS + " -i \"" + OUTPUT_DIR + "/frame_%04d.png\" -c:v libx264 -pix_fmt yuv420p \"" + OUTPUT_DIR + "/misreading_machine.mp4\"");
      exit();
    }
  }
}

void setupCamera(float t) {
  perspective(PI / 3.0, width / float(height), 5, 6000);

  float orbit = TWO_PI * CAMERA_SPEED * frameCount / FPS + 0.25 * sin(TWO_PI * t);
  float radius = lerp(760, 620, smoothStep(0.30, 0.80, t));
  float camY = lerp(-285, -155, smoothStep(0.35, 0.95, t)) + 34 * sin(TWO_PI * (t * 1.8 + 0.13));
  float lookY = lerp(35, -8, smoothStep(0.15, 0.90, t));

  camera(cos(orbit) * radius, camY, sin(orbit) * radius,
         0, lookY, 0,
         0, 1, 0);
}

void loadData() {
  Table yolo = loadCsvSmart(YOLO_CSV);
  if (yolo != null) {
    for (TableRow row : yolo.rows()) {
      String element = getStringAny(row, new String[] {"spatial_element", "yolo_element", "object", "label"}, "unknown");
      float conf = getFloatAny(row, new String[] {"conf", "confidence", "score"}, 0.55);
      float area = getFloatAny(row, new String[] {"area", "bbox_area"}, 1000);
      float cx = getFloatAny(row, new String[] {"center_x", "cx"}, 640);
      float cy = getFloatAny(row, new String[] {"center_y", "cy"}, 360);
      String src = getStringAny(row, new String[] {"source_image", "image", "filename"}, "");
      DetectionRow d = new DetectionRow(element, conf, max(1, area), cx, cy, src);
      detections.add(d);
      if (detections.size() == 1) {
        minArea = d.area;
        maxArea = d.area;
      } else {
        minArea = min(minArea, d.area);
        maxArea = max(maxArea, d.area);
      }
    }
  }

  Table matching = loadCsvSmart(MATCH_CSV);
  if (matching != null) {
    for (TableRow row : matching.rows()) {
      String element = getStringAny(row, new String[] {"yolo_element", "spatial_element", "object", "label"}, "unknown");
      float sim = getFloatAny(row, new String[] {"similarity_score", "score", "similarity"}, 0.12);
      String page = getStringAny(row, new String[] {"matched_arch_page", "reference", "page", "matched_page"}, "Courtyard");
      MatchStats ms = matchByElement.get(element);
      if (ms == null) {
        ms = new MatchStats();
        matchByElement.put(element, ms);
      }
      ms.add(sim, page);
    }
  }

  Table treatise = loadCsvSmart(TEXT_CSV);
  if (treatise != null) {
    float totalWords = 0;
    for (TableRow row : treatise.rows()) {
      totalWords += getFloatAny(row, new String[] {"word_count", "words", "length"}, 80);
      textRowCount++;
    }
    float avgWords = textRowCount > 0 ? totalWords / textRowCount : 80;
    textDensity = constrain(map(avgWords, 45, 155, 0.75, 1.85), 0.65, 2.2);
  }

  if (detections.size() == 0) {
    createFallbackDetections();
  }

  println("YOLO rows: " + detections.size());
  println("Matching element groups: " + matchByElement.size());
  println("Text rows: " + textRowCount + " | text density: " + nf(textDensity, 1, 2));
}

Table loadCsvSmart(String fileName) {
  String path = findExistingFile(fileName);
  if (path == null) {
    println("Missing CSV: " + fileName);
    return null;
  }
  try {
    return loadTable(path, "header,csv");
  } catch (Exception e) {
    println("Could not load CSV: " + path + " | " + e.getMessage());
    return null;
  }
}

String findExistingFile(String fileName) {
  String[] candidates = new String[] {
    sketchPath("data/" + fileName),
    PROJECT_DIR + "/" + fileName,
    EXTERNAL_ASSET_DIR + "/" + fileName,
    fileName
  };
  for (int i = 0; i < candidates.length; i++) {
    String clean = candidates[i].replace('\\', '/');
    if (new File(clean).exists()) return clean;
  }
  return null;
}

void loadModelsAndGeometry() {
  String rhinoPath = findExistingFile(RHINO_MODEL_FILE);
  if (rhinoPath != null) {
    rhinoShape = tryLoadShape(rhinoPath);
  }
  if (rhinoShape != null) {
    ArrayList<PVector> raw = new ArrayList<PVector>();
    collectVertices(rhinoShape, raw);
    rhinoVertices = normalizeVertices(sampleVertices(raw, 5200), 520, true);
    rhinoTargets = resampleVertices(rhinoVertices, max(PARTICLE_COUNT * 2, 3600));
  }
  if (rhinoTargets.size() < 64) {
    usingFallbackRhino = true;
    createFallbackCourtyard();
  }

  String camdenPath = findExistingFile(CAMDEN_MODEL_FILE);
  if (camdenPath == null) {
    camdenPath = findExistingFile(CAMDEN_MODEL_FALLBACK_FILE);
  }
  if (camdenPath != null) {
    if (camdenPath.toLowerCase().endsWith(".obj")) {
      ArrayList<PVector> raw = loadObjVerticesSampled(camdenPath, 6200);
      camdenVertices = normalizeVertices(raw, 650, true);
    } else {
      camdenShape = tryLoadShape(camdenPath);
      if (camdenShape != null) {
        ArrayList<PVector> raw = new ArrayList<PVector>();
        collectVertices(camdenShape, raw);
        camdenVertices = normalizeVertices(sampleVertices(raw, 6200), 650, true);
      }
    }
  }
  if (camdenVertices.size() >= 64) {
    for (PVector p : camdenVertices) {
      p.y += 60;
      p.x *= 0.86;
      p.z -= 120;
    }
  }
  if (camdenVertices.size() < 64) {
    usingFallbackCamden = true;
    camdenVertices = createFallbackCamdenCloud(5400);
  }
}

ArrayList<PVector> loadObjVerticesSampled(String path, int maxCount) {
  ArrayList<PVector> out = new ArrayList<PVector>();
  BufferedReader br = null;
  int seen = 0;
  try {
    br = createReader(path);
    String line;
    while ((line = br.readLine()) != null) {
      if (line.length() < 3 || line.charAt(0) != 'v' || line.charAt(1) != ' ') continue;
      String[] parts = splitTokens(line);
      if (parts.length < 4) continue;
      float x = parseFloat(parts[1]);
      float y = parseFloat(parts[2]);
      float z = parseFloat(parts[3]);
      if (Float.isNaN(x) || Float.isNaN(y) || Float.isNaN(z)) continue;

      PVector p = new PVector(x, y, z);
      if (out.size() < maxCount) {
        out.add(p);
      } else {
        int replace = int(random(seen + 1));
        if (replace < maxCount) out.set(replace, p);
      }
      seen++;
    }
  } catch (Exception e) {
    println("Could not stream OBJ vertices: " + path + " | " + e.getMessage());
  } finally {
    try {
      if (br != null) br.close();
    } catch (Exception e) {
    }
  }
  println("OBJ vertex sampler: " + out.size() + " sampled from " + seen + " vertices | " + path);
  return out;
}

PShape tryLoadShape(String path) {
  try {
    println("Loading model: " + path);
    PShape s = loadShape(path);
    if (s != null) {
      s.disableStyle();
    }
    return s;
  } catch (Exception e) {
    println("Could not load model: " + path + " | " + e.getMessage());
    return null;
  }
}

void collectVertices(PShape s, ArrayList<PVector> out) {
  if (s == null) return;
  int vc = s.getVertexCount();
  for (int i = 0; i < vc; i++) {
    PVector v = s.getVertex(i);
    if (v != null && isFinite(v)) {
      out.add(v.copy());
    }
  }
  int cc = s.getChildCount();
  for (int i = 0; i < cc; i++) {
    collectVertices(s.getChild(i), out);
  }
}

ArrayList<PVector> sampleVertices(ArrayList<PVector> src, int maxCount) {
  ArrayList<PVector> out = new ArrayList<PVector>();
  if (src.size() == 0) return out;
  int step = max(1, src.size() / maxCount);
  for (int i = 0; i < src.size() && out.size() < maxCount; i += step) {
    out.add(src.get(i).copy());
  }
  return out;
}

ArrayList<PVector> normalizeVertices(ArrayList<PVector> src, float targetSpan, boolean flipY) {
  ArrayList<PVector> out = new ArrayList<PVector>();
  if (src.size() == 0) return out;

  PVector mn = src.get(0).copy();
  PVector mx = src.get(0).copy();
  for (PVector p : src) {
    mn.x = min(mn.x, p.x); mn.y = min(mn.y, p.y); mn.z = min(mn.z, p.z);
    mx.x = max(mx.x, p.x); mx.y = max(mx.y, p.y); mx.z = max(mx.z, p.z);
  }

  PVector center = new PVector((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, (mn.z + mx.z) * 0.5);
  float span = max(max(mx.x - mn.x, mx.y - mn.y), mx.z - mn.z);
  float sc = targetSpan / max(0.0001, span);

  for (PVector p : src) {
    float y = (p.y - center.y) * sc;
    if (flipY) y *= -1;
    out.add(new PVector((p.x - center.x) * sc, y, (p.z - center.z) * sc));
  }
  return out;
}

ArrayList<PVector> resampleVertices(ArrayList<PVector> src, int count) {
  ArrayList<PVector> out = new ArrayList<PVector>();
  if (src.size() == 0) return out;
  for (int i = 0; i < count; i++) {
    int idx = int(map(i, 0, max(1, count - 1), 0, src.size() - 1));
    PVector p = src.get(idx).copy();
    float a = atan2(p.z, p.x);
    float r = sqrt(p.x * p.x + p.z * p.z);
    float ringPull = smoothStep(80, 310, r);
    p.x = lerp(p.x, cos(a) * constrain(r, 145, 330), 0.22 * ringPull);
    p.z = lerp(p.z, sin(a) * constrain(r, 145, 330), 0.22 * ringPull);
    out.add(p);
  }
  return out;
}

void createFallbackCourtyard() {
  rhinoVertices.clear();
  rhinoTargets.clear();
  fallbackBlocks.clear();

  int segments = 96;
  int rings = 3;
  for (int r = 0; r < rings; r++) {
    float radius = 155 + r * 82;
    float blockW = 20 + r * 3;
    float blockD = 42;
    for (int i = 0; i < segments; i++) {
      if ((i + r * 2) % 7 == 0) continue;
      float a = TWO_PI * i / segments;
      float h = 32 + 66 * noise(r * 12.7, i * 0.16);
      Block b = new Block(a, radius, blockW, blockD, h);
      fallbackBlocks.add(b);
      b.addVertices(rhinoVertices);
      for (int j = 0; j < 5; j++) {
        float da = random(-0.015, 0.015);
        float rr = radius + random(-blockD * 0.45, blockD * 0.45);
        float yy = -random(0, h);
        rhinoTargets.add(new PVector(cos(a + da) * rr, yy, sin(a + da) * rr));
      }
    }
  }

  while (rhinoTargets.size() < max(PARTICLE_COUNT * 2, 3600)) {
    float a = random(TWO_PI);
    float radius = random(150, 330);
    float y = -random(8, 110) * noise(a * 2.4, radius * 0.01);
    rhinoTargets.add(new PVector(cos(a) * radius, y, sin(a) * radius));
  }
}

ArrayList<PVector> createFallbackCamdenCloud(int count) {
  ArrayList<PVector> cloud = new ArrayList<PVector>();
  for (int i = 0; i < count; i++) {
    float lane = floor(random(5));
    float x = map(lane, 0, 4, -285, 285) + random(-34, 34);
    float z = random(-480, 185);
    float streetNoise = noise(x * 0.013, z * 0.012);
    float facade = random(1) < 0.68 ? 1 : 0;
    float y = facade == 1 ? -random(8, 210 * streetNoise + 24) : random(-5, 18);
    if (random(1) < 0.18) {
      x = random(-330, 330);
      z = random(-430, 240);
      y = -random(20, 130);
    }
    cloud.add(new PVector(x, y + 48, z));
  }
  return cloud;
}

void createFallbackDetections() {
  String[] elements = new String[] {"chair", "window", "door", "person", "car", "wall", "stairs", "bench"};
  for (int i = 0; i < 220; i++) {
    String e = elements[i % elements.length];
    float area = random(500, 68000);
    detections.add(new DetectionRow(e, random(0.45, 0.96), area, random(1280), random(720), "fallback"));
    minArea = i == 0 ? area : min(minArea, area);
    maxArea = i == 0 ? area : max(maxArea, area);
    MatchStats ms = matchByElement.get(e);
    if (ms == null) {
      ms = new MatchStats();
      matchByElement.put(e, ms);
    }
    ms.add(random(0.05, 0.42), i % 2 == 0 ? "Courtyard" : "Threshold");
  }
}

void createParticles() {
  particles.clear();
  for (int i = 0; i < PARTICLE_COUNT; i++) {
    DetectionRow d = detections.get(i % detections.size());
    MatchStats ms = matchByElement.get(d.element);
    float sim = ms == null ? 0.12 : ms.average();
    int pageGroup = ms == null ? 0 : ms.pageGroup();
    PVector origin = camdenVertices.get(int(random(camdenVertices.size()))).copy();
    int targetIndex = int(random(rhinoTargets.size()));
    particles.add(new Particle(i, d, sim, pageGroup, origin, targetIndex));
  }
}

void drawTextDrivenField(float t, float stageCity, float stageMorph) {
  pushMatrix();
  rotateY(0.08 * sin(TWO_PI * t));
  blendMode(ADD);

  int rings = int(9 * textDensity);
  for (int i = 0; i < rings; i++) {
    float r = 85 + i * 34 + 8 * sin(frameCount * 0.012 + i);
    float alpha = 22 + 18 * sin(frameCount * 0.018 + i * 0.7);
    stroke(20, 155 + i * 5, 210, alpha * (0.45 + stageMorph));
    strokeWeight(0.7);
    noFill();
    beginShape();
    int steps = 160;
    for (int j = 0; j <= steps; j++) {
      float a = TWO_PI * j / steps;
      float n = noise(cos(a) * 0.6 + i, sin(a) * 0.6, frameCount * 0.006);
      float rr = r + map(n, 0, 1, -13, 13) * (0.4 + stageMorph);
      vertex(cos(a) * rr, 3 + sin(a * 3 + t * TWO_PI) * 3, sin(a) * rr);
    }
    endShape();
  }

  int radial = int(64 * textDensity);
  for (int i = 0; i < radial; i++) {
    float a = TWO_PI * i / radial + frameCount * 0.0008;
    float inner = 92 + 10 * sin(i);
    float outer = 360 + 28 * noise(i * 0.11, frameCount * 0.006);
    float alpha = 12 + 34 * stageCity;
    stroke(65, 180, 255, alpha);
    strokeWeight(0.55);
    line(cos(a) * inner, 10, sin(a) * inner, cos(a) * outer, -4, sin(a) * outer);
  }

  blendMode(BLEND);
  popMatrix();
}

void drawCourtyardFrame(float t, float stageMorph, float stageCourtyard) {
  pushMatrix();
  rotateY(0.035 * sin(TWO_PI * t * 1.2));

  float alpha = lerp(58, 120, stageCourtyard);
  blendMode(ADD);

  if (usingFallbackRhino) {
    for (Block b : fallbackBlocks) {
      b.drawWire(alpha, stageCourtyard);
    }
  } else {
    stroke(65, 210, 255, alpha);
    strokeWeight(0.85);
    noFill();
    int limit = min(rhinoVertices.size() - 3, 4200);
    for (int i = 0; i < limit; i += 3) {
      PVector a = rhinoVertices.get(i);
      PVector b = rhinoVertices.get(i + 1);
      PVector c = rhinoVertices.get(i + 2);
      if (PVector.dist(a, b) < 130) line(a.x, a.y, a.z, b.x, b.y, b.z);
      if (PVector.dist(b, c) < 130) line(b.x, b.y, b.z, c.x, c.y, c.z);
      if (PVector.dist(c, a) < 130) line(c.x, c.y, c.z, a.x, a.y, a.z);
    }
  }

  stroke(255, 128, 38, 42 + 80 * stageCourtyard);
  strokeWeight(1.2);
  noFill();
  for (int i = 0; i < 3; i++) {
    float r = 155 + i * 82;
    beginShape();
    for (int j = 0; j <= 192; j++) {
      float a = TWO_PI * j / 192;
      float wave = 5 * sin(a * 8 + frameCount * 0.018 + i);
      vertex(cos(a) * (r + wave), -1, sin(a) * (r + wave));
    }
    endShape();
  }

  blendMode(BLEND);
  popMatrix();
}

void drawCamdenMemory(float t, float visibility) {
  if (visibility <= 0.01) return;
  pushMatrix();
  blendMode(ADD);
  float v = constrain(visibility, 0, 1);
  strokeWeight(1.1);
  int step = max(1, camdenVertices.size() / 1800);
  for (int i = 0; i < camdenVertices.size(); i += step) {
    PVector p = camdenVertices.get(i);
    float pulse = noise(i * 0.03, frameCount * 0.012);
    stroke(90, 150, 255, (18 + 70 * pulse) * v);
    point(p.x + 4 * sin(frameCount * 0.012 + i), p.y, p.z);
  }
  blendMode(BLEND);
  popMatrix();
}

void drawParticleField(float t, float stageMorph, float stageCourtyard) {
  blendMode(ADD);
  for (Particle p : particles) {
    p.update(t, stageMorph, stageCourtyard);
    p.draw();
  }
  blendMode(BLEND);
}

void drawMachineHalo(float t, float stageCourtyard) {
  pushMatrix();
  blendMode(ADD);
  rotateY(frameCount * 0.002);

  int bands = 5;
  for (int b = 0; b < bands; b++) {
    float y = -22 - b * 18 + 18 * sin(frameCount * 0.01 + b);
    float r = 115 + b * 52;
    stroke(255, 122, 42, (18 + 34 * stageCourtyard) * (1.0 - b * 0.1));
    strokeWeight(0.8);
    noFill();
    beginShape();
    for (int i = 0; i <= 180; i++) {
      float a = TWO_PI * i / 180;
      float rr = r + 10 * noise(cos(a) + b, sin(a) + b, frameCount * 0.01);
      vertex(cos(a) * rr, y, sin(a) * rr);
    }
    endShape();
  }

  blendMode(BLEND);
  popMatrix();
}

void drawHud(float t) {
  hint(DISABLE_DEPTH_TEST);
  camera();
  perspective();
  noLights();

  blendMode(ADD);
  textFont(hudFont);
  textAlign(LEFT, TOP);
  fill(125, 220, 255, 145);
  String stage = t < 0.25 ? "01 machine vision scan" : (t < 0.58 ? "02 spatial misreading" : "03 machine-readable courtyard");
  text("THE MISREADING MACHINE", 28, 24);
  fill(255, 150, 70, 120);
  text(stage, 28, 43);

  float barW = 220;
  noFill();
  stroke(75, 180, 240, 90);
  rect(28, height - 35, barW, 5);
  noStroke();
  fill(255, 130, 50, 130);
  rect(28, height - 35, barW * t, 5);

  fill(125, 220, 255, 95);
  String status = (usingFallbackRhino ? "procedural ring" : "Rhino2.obj") + " / " + (usingFallbackCamden ? "synthetic Camden cloud" : CAMDEN_MODEL_FILE);
  text(status, 28, height - 58);

  blendMode(BLEND);
  hint(ENABLE_DEPTH_TEST);
}

String getStringAny(TableRow row, String[] names, String fallback) {
  for (int i = 0; i < names.length; i++) {
    try {
      String v = row.getString(names[i]);
      if (v != null && v.length() > 0) return v;
    } catch (Exception e) {
    }
  }
  return fallback;
}

float getFloatAny(TableRow row, String[] names, float fallback) {
  for (int i = 0; i < names.length; i++) {
    try {
      String v = row.getString(names[i]);
      if (v != null && v.length() > 0) {
        float f = parseFloat(v);
        if (!Float.isNaN(f)) return f;
      }
    } catch (Exception e) {
    }
    try {
      float f = row.getFloat(names[i]);
      if (!Float.isNaN(f)) return f;
    } catch (Exception e) {
    }
  }
  return fallback;
}

float smoothStep(float edge0, float edge1, float x) {
  float u = constrain((x - edge0) / max(0.0001, edge1 - edge0), 0, 1);
  return u * u * (3 - 2 * u);
}

boolean isFinite(PVector p) {
  return !Float.isNaN(p.x) && !Float.isNaN(p.y) && !Float.isNaN(p.z) &&
         !Float.isInfinite(p.x) && !Float.isInfinite(p.y) && !Float.isInfinite(p.z);
}

int colorForElement(String element, int pageGroup) {
  int h = abs(element.hashCode());
  int idx = (h + pageGroup) % palette.length;
  return palette[idx];
}

class DetectionRow {
  String element;
  float confidence;
  float area;
  float centerX;
  float centerY;
  String source;

  DetectionRow(String element, float confidence, float area, float centerX, float centerY, String source) {
    this.element = element;
    this.confidence = constrain(confidence, 0, 1);
    this.area = area;
    this.centerX = centerX;
    this.centerY = centerY;
    this.source = source;
  }

  float areaNorm() {
    float la = log(max(1, area));
    float lmin = log(max(1, minArea));
    float lmax = log(max(2, maxArea));
    return constrain(norm(la, lmin, lmax), 0, 1);
  }
}

class MatchStats {
  float simTotal = 0;
  int count = 0;
  String page = "Courtyard";

  void add(float sim, String pageName) {
    simTotal += constrain(sim, 0, 1);
    count++;
    if (pageName != null && pageName.length() > 0) page = pageName;
  }

  float average() {
    return count == 0 ? 0.12 : simTotal / count;
  }

  int pageGroup() {
    return (page.hashCode() & 0x7fffffff) % 6;
  }
}

class Particle {
  PVector pos;
  PVector prev;
  PVector origin;
  int targetIndex;
  int pageGroup;
  String element;
  float confidence;
  float areaN;
  float similarity;
  float speed;
  float size;
  float phase;
  float delay;
  float waveAmp;
  int baseColor;

  Particle(int id, DetectionRow d, float similarity, int pageGroup, PVector origin, int targetIndex) {
    this.origin = origin;
    this.pos = origin.copy();
    this.prev = origin.copy();
    this.targetIndex = targetIndex;
    this.pageGroup = pageGroup;
    this.element = d.element;
    this.confidence = d.confidence;
    this.areaN = d.areaNorm();
    this.similarity = constrain(similarity, 0, 1);
    this.speed = FLOW_SPEED * lerp(0.45, 2.25, this.similarity) * lerp(0.75, 1.35, d.confidence);
    this.size = POINT_SIZE * lerp(0.65, 2.25, sqrt(areaN));
    this.phase = random(TWO_PI);
    this.delay = random(-0.08, 0.16);
    this.waveAmp = lerp(12, 82, this.similarity);
    this.baseColor = colorForElement(d.element, pageGroup);
  }

  void update(float t, float stageMorph, float stageCourtyard) {
    prev.set(pos);

    float localMorph = smoothStep(0.20 + delay, 0.62 + delay, t);
    float travel = frameCount * 0.035 * speed + targetIndex;
    int idxA = floor(travel) % rhinoTargets.size();
    int idxB = (idxA + 1 + pageGroup * 17) % rhinoTargets.size();
    float f = travel - floor(travel);
    PVector a = rhinoTargets.get(idxA);
    PVector b = rhinoTargets.get(idxB);

    PVector target = PVector.lerp(a, b, f);
    float theta = atan2(target.z, target.x);
    float radialNoise = map(noise(theta * 1.7 + phase, frameCount * 0.008), 0, 1, -1, 1);
    target.x += cos(theta) * radialNoise * (8 + 22 * similarity);
    target.z += sin(theta) * radialNoise * (8 + 22 * similarity);
    target.y += sin(frameCount * 0.028 * speed + phase + theta * 3.0) * waveAmp * (0.25 + 0.75 * stageCourtyard);

    PVector city = origin.copy();
    city.x += sin(frameCount * 0.012 + phase) * 12;
    city.y += cos(frameCount * 0.017 + phase) * 5;
    city.z += frameCount * 0.18 * speed;
    if (city.z > 270) city.z -= 760;

    pos.set(PVector.lerp(city, target, localMorph));
  }

  void draw() {
    float pulse = 0.65 + 0.35 * sin(frameCount * 0.04 * speed + phase);
    float alpha = lerp(38, 155, confidence) * pulse;
    stroke(red(baseColor), green(baseColor), blue(baseColor), alpha);
    strokeWeight(size);
    point(pos.x, pos.y, pos.z);

    stroke(red(baseColor), green(baseColor), blue(baseColor), alpha * 0.28);
    strokeWeight(max(0.55, size * 0.34));
    line(prev.x, prev.y, prev.z, pos.x, pos.y, pos.z);
  }
}

class Block {
  float angle;
  float radius;
  float w;
  float d;
  float h;
  PVector[] v = new PVector[8];

  Block(float angle, float radius, float w, float d, float h) {
    this.angle = angle;
    this.radius = radius;
    this.w = w;
    this.d = d;
    this.h = h;
    build();
  }

  void build() {
    PVector radial = new PVector(cos(angle), 0, sin(angle));
    PVector tangent = new PVector(-sin(angle), 0, cos(angle));
    PVector center = PVector.mult(radial, radius);
    int idx = 0;
    for (int yi = 0; yi < 2; yi++) {
      float y = yi == 0 ? 0 : -h;
      for (int sx = -1; sx <= 1; sx += 2) {
        for (int sz = -1; sz <= 1; sz += 2) {
          PVector p = center.copy();
          p.add(PVector.mult(tangent, sx * w * 0.5));
          p.add(PVector.mult(radial, sz * d * 0.5));
          p.y = y;
          v[idx++] = p;
        }
      }
    }
  }

  void addVertices(ArrayList<PVector> out) {
    for (int i = 0; i < v.length; i++) out.add(v[i].copy());
  }

  void drawWire(float alpha, float stageCourtyard) {
    stroke(55, 205, 255, alpha);
    strokeWeight(0.75 + 0.45 * stageCourtyard);
    lineV(0, 1); lineV(1, 3); lineV(3, 2); lineV(2, 0);
    lineV(4, 5); lineV(5, 7); lineV(7, 6); lineV(6, 4);
    lineV(0, 4); lineV(1, 5); lineV(2, 6); lineV(3, 7);
  }

  void lineV(int a, int b) {
    line(v[a].x, v[a].y, v[a].z, v[b].x, v[b].y, v[b].z);
  }
}
