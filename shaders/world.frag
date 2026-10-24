// Dérive: open-world Paris in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
#version 330 core

in vec3 vWorld;
in vec3 vNormal;
in vec2 vUV;
in vec4 vShadowPos;
flat in float vMat;
flat in float vSeed;

uniform vec3 uCamPos;
uniform vec3 uSunDir;        // towards the sun
uniform vec3 uSunColor;
uniform vec3 uSkyZenith;
uniform vec3 uSkyHorizon;
uniform float uFogDensity;
uniform float uTime;
uniform vec3 uCarColor;
uniform sampler2DShadow uShadowMap;
uniform int uShadows;
uniform vec3 uAmbSky;        // ambient from the sky dome (linear)
uniform vec3 uAmbGround;     // ambient bounced from the ground
uniform float uNight;        // 0 day .. 1 night: lit windows and lamps
uniform float uTowerLights;  // the Eiffel Tower lit (0 after 23:45)
uniform float uSparkle;      // 0 .. 1: the tower sparkles
uniform float uSnowCover;    // 0 .. 1: snow lying on the ground, roofs and trees
uniform float uXmas;         // 1 in the Christmas season: lights in the trees
uniform float uGallery;      // 1 while drawing the inside of the Louvre
uniform float uAutumn;       // 0 .. 1: the leaves turning yellow, orange and brown
uniform float uBare;         // 0 .. 1: the trees losing their leaves (winter)
uniform float uLitter;       // 0 .. 1: fallen leaves on the ground
uniform vec4 uErase[4];      // Paris in 1973: buildings not there yet (centre xz, half sizes)
uniform vec4 uEraseB[4];     //   their turn (cos, sin) and the ground under them (y)
uniform int uEraseN;
uniform float uEra;          // 1: the colours of a Kodachrome of 1973

bool erased(vec3 p)
{
    for (int i = 0; i < uEraseN; i++) {
        vec2 d = p.xz - uErase[i].xy;
        float u = dot(d, uEraseB[i].xy);
        float v = dot(d, vec2(-uEraseB[i].y, uEraseB[i].x));
        if (abs(u) < uErase[i].z && abs(v) < uErase[i].w && p.y > uEraseB[i].z) return true;
    }
    return false;
}

// Warm, a little faded and contrasty, the blacks lifted: a slide of 1973
vec3 kodachrome(vec3 c)
{
    float l = dot(c, vec3(0.3, 0.55, 0.15));
    c = mix(vec3(l), c, 0.82);
    c *= vec3(1.08, 1.0, 0.82);
    c = c * 0.94 + vec3(0.025, 0.018, 0.01);
    return c;
}
uniform float uTrash;        // 0 .. 1: paper, cans and bottles the morning after a fête
uniform vec4 uLights[64];    // street lamps: xyz position, w intensity
uniform int uLightCount;
uniform vec3 uHeadPos;       // player's headlights
uniform vec3 uHeadDir;
uniform float uHeadOn;
uniform vec3 uExtraColor;    // pedestrians: skin
uniform vec3 uExtraColor2;   // pedestrians: trousers
uniform float uWet;          // 0 dry .. 1 soaked streets
uniform float uMist;         // 0 .. 1: mist lying on the Seine in the morning
uniform float uMistY;        // the water's level, where it is thickest
uniform float uHeat;         // 0 .. 1: a hot afternoon, the roads shimmer
uniform float uBlossom;      // 0 .. 1: spring, the cherries and chestnuts in flower
uniform float uPetals;       // 0 .. 1: their petals on the ground

out vec4 fragColor;

float gAlpha = 1.0;   // < 1 only for see-through lattice (alpha to coverage)

// ---------------------------------------------------------------- noise ---

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p)
{
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p)
{
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { s += a * noise(p); p *= 2.03; a *= 0.5; }
    return s;
}

// Integral of a unit-periodic pulse that is 1 on [a,b]
float pulseIntegral(float t, float a, float b)
{
    return floor(t) * (b - a) + clamp(fract(t), a, b) - a;
}

// Box-filtered periodic pulse: anti-aliased window/stripe patterns
float fpulse(float a, float b, float x, float w)
{
    w = max(w, 1e-4);
    return (pulseIntegral(x + 0.5 * w, a, b) - pulseIntegral(x - 0.5 * w, a, b)) / w;
}

vec3 toLinear(vec3 c) { return pow(c, vec3(2.2)); }


// ---------------------------------------------------------------------------
//  Paintings in the Louvre, painted here (public domain works, our own
//  simple renderings).  uv runs across the canvas, v upwards.
// ---------------------------------------------------------------------------

// soft-edged ellipse mask
float blob(vec2 p, vec2 c, vec2 r)
{
    vec2 q = (p - c) / r;
    return 1.0 - smoothstep(0.85, 1.0, dot(q, q));
}

float band(float x, float a, float b, float w) { return smoothstep(a - w, a, x) * (1.0 - smoothstep(b, b + w, x)); }

// Leonardo: the Mona Lisa
vec3 monaLisa(vec2 uv)
{
    float n = fbm(uv * 9.0);
    // the hazy landscape: blue-green distance, brown rocks, winding road
    vec3 c = mix(vec3(0.42, 0.46, 0.36), vec3(0.62, 0.66, 0.55), smoothstep(0.55, 1.0, uv.y));
    c = mix(c, vec3(0.35, 0.3, 0.2), smoothstep(0.62, 0.45, uv.y) * (0.6 + 0.4 * n));
    c = mix(c, vec3(0.55, 0.45, 0.28),
            band(abs(uv.x - 0.2 - 0.06 * sin(uv.y * 30.0)), 0.0, 0.02, 0.01) * step(0.45, uv.y) * step(uv.y, 0.6));
    // hair and veil behind the face, falling to the shoulders
    float hair = max(blob(uv, vec2(0.5, 0.69), vec2(0.15, 0.17)),
                     max(blob(uv, vec2(0.38, 0.54), vec2(0.05, 0.13)), blob(uv, vec2(0.62, 0.54), vec2(0.05, 0.13))));
    c = mix(c, vec3(0.1, 0.07, 0.04), hair);
    // the dark dress, shoulders and arms
    float dress = max(blob(uv, vec2(0.5, 0.28), vec2(0.47, 0.3)), step(uv.y, 0.25) * step(abs(uv.x - 0.5), 0.48));
    c = mix(c, vec3(0.16, 0.12, 0.07) * (0.8 + 0.4 * fbm(uv * vec2(12.0, 4.0))), dress);
    // neckline and chest
    float chest = blob(uv, vec2(0.5, 0.5), vec2(0.15, 0.065)) * step(uv.y, 0.53);
    vec3 skin = vec3(0.8, 0.6, 0.36);
    c = mix(c, skin * 0.95, chest);
    c = mix(c, skin * 0.9, blob(uv, vec2(0.5, 0.57), vec2(0.045, 0.06)));          // neck
    // the face, lit from the left
    float face = blob(uv, vec2(0.5, 0.68), vec2(0.088, 0.115));
    c = mix(c, skin * (1.0 - 0.35 * smoothstep(0.45, 0.58, uv.x)), face);
    // eyes, the nose's shadow, the smile
    c = mix(c, vec3(0.25, 0.16, 0.08), blob(uv, vec2(0.468, 0.70), vec2(0.016, 0.007)));
    c = mix(c, vec3(0.25, 0.16, 0.08), blob(uv, vec2(0.532, 0.70), vec2(0.016, 0.007)));
    c = mix(c, skin * 0.7, blob(uv, vec2(0.515, 0.66), vec2(0.008, 0.02)));
    c = mix(c, vec3(0.45, 0.25, 0.15), blob(uv, vec2(0.5, 0.627), vec2(0.03, 0.004)));
    // the hands, one over the other
    c = mix(c, skin, blob(uv, vec2(0.46, 0.2), vec2(0.13, 0.045)));
    c = mix(c, skin * 1.04, blob(uv, vec2(0.56, 0.22), vec2(0.12, 0.04)));
    // old varnish: yellowed, darker at the edges, fine cracks
    c *= vec3(0.98, 0.88, 0.62) * (0.75 + 0.25 * smoothstep(0.75, 0.2, length(uv - 0.5)));
    c *= 0.92 + 0.08 * step(0.08, fract(fbm(uv * 60.0) * 4.0));
    return c;
}

// Delacroix: Liberty Leading the People
vec3 liberty(vec2 uv)
{
    float n = fbm(uv * 6.0);
    vec3 c = mix(vec3(0.75, 0.68, 0.5), vec3(0.45, 0.42, 0.38), n);            // smoke and sky
    c = mix(c, vec3(0.92, 0.85, 0.6), blob(uv, vec2(0.62, 0.62), vec2(0.25, 0.3)) * 0.6);
    // the barricade and the fallen
    c = mix(c, vec3(0.2, 0.17, 0.13) * (0.7 + 0.6 * n), step(uv.y, 0.22 + 0.08 * sin(uv.x * 9.0)));
    c = mix(c, vec3(0.7, 0.62, 0.5), blob(uv, vec2(0.35, 0.12), vec2(0.18, 0.05)));
    // Liberty: yellow dress, bare shoulder, raised arm with the flag
    c = mix(c, vec3(0.86, 0.76, 0.48), blob(uv, vec2(0.52, 0.45), vec2(0.07, 0.22)));
    c = mix(c, vec3(0.8, 0.62, 0.45), blob(uv, vec2(0.53, 0.7), vec2(0.035, 0.05)));
    c = mix(c, vec3(0.15, 0.1, 0.08), blob(uv, vec2(0.53, 0.73), vec2(0.035, 0.03)));   // Phrygian cap
    float arm = band(uv.x - 0.53 - (uv.y - 0.65) * 0.25, 0.0, 0.02, 0.005) * band(uv.y, 0.65, 0.85, 0.01);
    c = mix(c, vec3(0.8, 0.62, 0.45), arm);
    float pole = band(uv.x - 0.56 - (uv.y - 0.6) * 0.3, 0.0, 0.006, 0.002) * band(uv.y, 0.6, 0.98, 0.01);
    c = mix(c, vec3(0.2, 0.15, 0.1), pole);
    float fx = (uv.x - 0.6) / 0.18;
    float flag = band(uv.y - 0.03 * sin(fx * 6.0), 0.82, 0.96, 0.005) * band(fx, 0.0, 1.0, 0.01);
    vec3 tri = fx < 0.33 ? vec3(0.15, 0.25, 0.6) : fx < 0.66 ? vec3(0.9, 0.88, 0.8) : vec3(0.75, 0.12, 0.1);
    c = mix(c, tri, flag);
    // the man in the top hat, the boy with pistols
    c = mix(c, vec3(0.08, 0.07, 0.07), blob(uv, vec2(0.33, 0.45), vec2(0.05, 0.16)));
    c = mix(c, vec3(0.05, 0.05, 0.05), blob(uv, vec2(0.33, 0.66), vec2(0.03, 0.04)));
    c = mix(c, vec3(0.3, 0.25, 0.2), blob(uv, vec2(0.68, 0.38), vec2(0.04, 0.13)));
    return c * vec3(0.95, 0.9, 0.78);
}

// Géricault: The Raft of the Medusa
vec3 medusa(vec2 uv)
{
    float n = fbm(uv * 7.0);
    vec3 c = mix(vec3(0.15, 0.13, 0.1), vec3(0.55, 0.45, 0.3), smoothstep(0.3, 0.9, uv.y) * (0.5 + 0.6 * n));
    c = mix(c, vec3(0.85, 0.7, 0.45), blob(uv, vec2(0.85, 0.55), vec2(0.18, 0.12)) * 0.8);   // the light
    c = mix(c, vec3(0.08, 0.1, 0.09) * (0.7 + 0.5 * n), step(uv.y, 0.25 + 0.05 * sin(uv.x * 14.0)));  // the sea
    // the raft and its mast and sail
    c = mix(c, vec3(0.2, 0.15, 0.1), band(uv.y, 0.18, 0.28, 0.01) * band(uv.x, 0.08, 0.9, 0.01));
    c = mix(c, vec3(0.12, 0.1, 0.08), band(uv.x - 0.33 + uv.y * 0.05, 0.0, 0.008, 0.002) * band(uv.y, 0.25, 0.9, 0.01));
    float sail = step(0.0, (uv.x - 0.2) - (uv.y - 0.4) * 0.3) * step(uv.x, 0.33) * band(uv.y, 0.4, 0.8, 0.01);
    c = mix(c, vec3(0.5, 0.42, 0.3), sail);
    // the bodies, piled up towards the man waving
    for (int k = 0; k < 9; k++) {
        float fk = float(k);
        vec2 p = vec2(0.42 + fk * 0.05, 0.3 + fk * 0.045);
        c = mix(c, vec3(0.72, 0.58, 0.42) * (0.7 + 0.3 * fract(fk * 0.37)), blob(uv, p, vec2(0.035, 0.06)));
    }
    c = mix(c, vec3(0.8, 0.75, 0.65), blob(uv, vec2(0.84, 0.78), vec2(0.03, 0.035)));        // the cloth
    return c;
}

// David: The Coronation of Napoleon
vec3 coronation(vec2 uv)
{
    float n = fbm(uv * 10.0);
    vec3 c = mix(vec3(0.3, 0.26, 0.2), vec3(0.45, 0.38, 0.28), n);                          // the choir of Notre-Dame
    c = mix(c, vec3(0.2, 0.17, 0.13), band(fract(uv.x * 5.0), 0.4, 0.6, 0.05) * step(0.6, uv.y)); // pillars
    // the crowd: rows of heads and coats, red, gold and black
    for (int r = 0; r < 3; r++) {
        float y = 0.3 + float(r) * 0.12;
        float cell = floor(uv.x * 28.0);
        float h = fract(sin(cell * 12.9 + float(r) * 7.0) * 43758.5);
        vec3 coat = h < 0.35 ? vec3(0.6, 0.1, 0.08) : h < 0.6 ? vec3(0.75, 0.6, 0.25) : vec3(0.1, 0.08, 0.08);
        c = mix(c, coat, step(uv.y, y) * step(y - 0.12, uv.y) * step(0.15, fract(uv.x * 28.0)));
        c = mix(c, vec3(0.8, 0.62, 0.48), blob(vec2(fract(uv.x * 28.0), uv.y), vec2(0.55, y + 0.02), vec2(0.25, 0.02)));
    }
    // Napoleon in his red cloak, raising the crown; Joséphine kneeling
    c = mix(c, vec3(0.7, 0.08, 0.08), blob(uv, vec2(0.6, 0.45), vec2(0.05, 0.2)));
    c = mix(c, vec3(0.8, 0.65, 0.5), blob(uv, vec2(0.6, 0.68), vec2(0.015, 0.025)));
    c = mix(c, vec3(0.9, 0.75, 0.25), blob(uv, vec2(0.58, 0.75), vec2(0.015, 0.01)));
    c = mix(c, vec3(0.92, 0.88, 0.8), blob(uv, vec2(0.48, 0.25), vec2(0.06, 0.08)));
    c = mix(c, vec3(0.65, 0.1, 0.1), blob(uv, vec2(0.42, 0.2), vec2(0.1, 0.04)));
    return c;
}

// a still life: fruit and a jug on a table
vec3 stillLife(vec2 uv)
{
    vec3 c = mix(vec3(0.12, 0.1, 0.08), vec3(0.25, 0.2, 0.14), fbm(uv * 5.0));
    c = mix(c, vec3(0.35, 0.22, 0.12), step(uv.y, 0.35));
    c = mix(c, vec3(0.85, 0.8, 0.7), blob(uv, vec2(0.3, 0.5), vec2(0.1, 0.17)));
    c = mix(c, vec3(0.75, 0.15, 0.1), blob(uv, vec2(0.55, 0.42), vec2(0.07, 0.07)));
    c = mix(c, vec3(0.85, 0.65, 0.15), blob(uv, vec2(0.68, 0.4), vec2(0.06, 0.06)));
    c = mix(c, vec3(0.3, 0.5, 0.15), blob(uv, vec2(0.62, 0.48), vec2(0.06, 0.05)));
    return c;
}

vec3 skyColor(vec3 dir)
{
    float t = pow(clamp(dir.y, 0.0, 1.0), 0.5);
    return mix(uSkyHorizon, uSkyZenith, t);
}

// ------------------------------------------------------------ materials ---


// ---------------------------------------------------------------------------
// Canvases from a seed: the pattern (seed mod 16), the colours (next 3
// bits) and a variant; uv runs over the canvas.
// ---------------------------------------------------------------------------

float h1(float n) { return fract(sin(n * 12.9898 + 4.1414) * 43758.5453); }

vec3 seedPalette(float p, int k)
{
    const vec3 P[40] = vec3[](
        // 0 Bauhaus
        vec3(0.93, 0.90, 0.82), vec3(0.85, 0.15, 0.12), vec3(0.10, 0.25, 0.60), vec3(0.95, 0.75, 0.10), vec3(0.08, 0.08, 0.08),
        // 1 deep reds
        vec3(0.45, 0.08, 0.06), vec3(0.80, 0.30, 0.10), vec3(0.95, 0.55, 0.20), vec3(0.25, 0.05, 0.08), vec3(0.65, 0.12, 0.15),
        // 2 the sea
        vec3(0.02, 0.10, 0.20), vec3(0.05, 0.35, 0.55), vec3(0.30, 0.70, 0.80), vec3(0.85, 0.95, 0.95), vec3(0.95, 0.60, 0.40),
        // 3 pastels
        vec3(0.97, 0.88, 0.85), vec3(0.75, 0.85, 0.95), vec3(0.80, 0.92, 0.80), vec3(0.98, 0.93, 0.70), vec3(0.85, 0.75, 0.92),
        // 4 neon night
        vec3(0.03, 0.02, 0.08), vec3(0.95, 0.10, 0.55), vec3(0.10, 0.90, 0.95), vec3(0.60, 0.20, 0.95), vec3(0.95, 0.95, 0.30),
        // 5 earth
        vec3(0.90, 0.85, 0.75), vec3(0.60, 0.42, 0.25), vec3(0.25, 0.18, 0.12), vec3(0.40, 0.45, 0.30), vec3(0.82, 0.70, 0.50),
        // 6 terracotta
        vec3(0.96, 0.94, 0.90), vec3(0.85, 0.47, 0.34), vec3(0.20, 0.18, 0.16), vec3(0.94, 0.78, 0.62), vec3(0.55, 0.30, 0.22),
        // 7 Klein blue
        vec3(0.95, 0.95, 0.97), vec3(0.0, 0.18, 0.65), vec3(0.05, 0.08, 0.35), vec3(0.30, 0.45, 0.85), vec3(0.0, 0.03, 0.12));
    return P[k * 5 + int(clamp(p, 0.0, 4.0))];
}

vec3 seeded(vec2 uv, float seed)
{
    int style = int(mod(seed, 16.0));
    int pk = int(mod(floor(seed / 16.0), 8.0));
    float s = floor(seed / 128.0) * 7.13 + float(style) * 1.7 + float(pk) * 0.37;
    vec3 c = seedPalette(0.0, pk);
    vec3 ink = seedPalette(4.0, pk);
    float r1 = h1(s + 2.0), r2 = h1(s + 3.0), r3 = h1(s + 4.0);
    if (style == 0) {             // a grid of cells
        vec2 lo = vec2(0.0), hi = vec2(1.0);
        float line = 1.0;
        for (int k = 0; k < 7; k++) {
            float cut = mix(0.28, 0.72, h1(s + 10.0 + float(k) * 3.7));
            if (h1(s + 30.0 + float(k)) < 0.5) {
                float x = mix(lo.x, hi.x, cut);
                line = min(line, abs(uv.x - x));
                if (uv.x < x) hi.x = x; else lo.x = x;
            } else {
                float y = mix(lo.y, hi.y, cut);
                line = min(line, abs(uv.y - y));
                if (uv.y < y) hi.y = y; else lo.y = y;
            }
        }
        float cell = h1(dot(lo + hi, vec2(13.1, 7.7)) + s);
        c = cell < 0.5 ? seedPalette(0.0, pk) : seedPalette(1.0 + floor((cell - 0.5) * 6.0), pk);
        c = mix(vec3(0.04), c, smoothstep(0.004, 0.009, line));
    } else if (style == 1) {      // soft-edged fields
        float w = 0.012 + 0.03 * r1;
        float wob = 0.01 * (noise(uv * 30.0 + s) - 0.5);
        float x = smoothstep(0.07, 0.07 + w, uv.x + wob) * (1.0 - smoothstep(0.93 - w, 0.93, uv.x + wob));
        float split = 0.35 + 0.3 * r2;
        float a = x * smoothstep(0.06, 0.06 + w, uv.y + wob) * (1.0 - smoothstep(split - 0.03 - w, split - 0.03, uv.y + wob));
        float b = x * smoothstep(split + 0.03, split + 0.03 + w, uv.y + wob) * (1.0 - smoothstep(0.94 - w, 0.94, uv.y + wob));
        c = mix(seedPalette(0.0, pk), seedPalette(1.0, pk), a);
        c = mix(c, seedPalette(2.0 + floor(r3 * 2.0), pk), b);
        c *= 0.92 + 0.08 * noise(uv * 80.0);
    } else if (style == 2) {      // circles and lines
        for (int k = 0; k < 8; k++) {
            vec2 ctr = vec2(h1(s + float(k) * 5.1), h1(s + float(k) * 5.1 + 1.0));
            float rad = 0.04 + 0.22 * h1(s + float(k) * 5.1 + 2.0);
            float d = length(uv - ctr);
            vec3 col = seedPalette(1.0 + mod(float(k), 4.0), pk);
            if (h1(s + float(k) * 9.3) < 0.6) c = mix(c, col, 1.0 - smoothstep(rad - 0.004, rad, d));
            else c = mix(c, col, 1.0 - smoothstep(0.004, 0.009, abs(d - rad)));
        }
        for (int k = 0; k < 4; k++) {
            vec2 a = vec2(h1(s + 50.0 + float(k)), h1(s + 60.0 + float(k)));
            vec2 b = vec2(h1(s + 70.0 + float(k)), h1(s + 80.0 + float(k)));
            vec2 pa = uv - a, ba = b - a;
            float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
            c = mix(c, ink, 1.0 - smoothstep(0.002, 0.005, length(pa - ba * t)));
        }
    } else if (style == 3) {      // arcs on tiles
        float n = 4.0 + floor(r1 * 9.0);
        vec2 g = uv * n;
        vec2 id = floor(g), f = fract(g);
        if (hash(id + s) < 0.5) f.x = 1.0 - f.x;
        float d = min(abs(length(f) - 0.5), abs(length(f - 1.0) - 0.5));
        float band = smoothstep(0.09 + 0.1 * r2, 0.07 + 0.1 * r2, d);
        c = mix(seedPalette(0.0, pk), seedPalette(1.0 + floor(hash(id + s + 3.0) * 2.0), pk), band);
    } else if (style == 4) {      // waves
        float v = 0.0;
        for (int k = 0; k < 3; k++) {
            vec2 ctr = vec2(h1(s + float(k) * 3.3), h1(s + float(k) * 3.3 + 1.0)) * 1.4 - 0.2;
            v += sin(length(uv - ctr) * (30.0 + 40.0 * r1));
        }
        v = v / 6.0 + 0.5;
        c = mix(seedPalette(1.0, pk), seedPalette(2.0, pk), smoothstep(0.3, 0.7, v));
        c = mix(c, seedPalette(3.0, pk), smoothstep(0.75, 0.95, v));
    } else if (style == 5) {      // cells
        float best = 9.0, second = 9.0, id = 0.0;
        for (int k = 0; k < 16; k++) {
            vec2 p = vec2(h1(s + float(k) * 2.7), h1(s + float(k) * 2.7 + 1.0));
            float d = length(uv - p);
            if (d < best) { second = best; best = d; id = float(k); }
            else if (d < second) second = d;
        }
        c = seedPalette(1.0 + mod(id, 4.0), pk) * (0.85 + 0.15 * h1(id + s));
        c = mix(ink, c, smoothstep(0.006, 0.014, second - best));
    } else if (style == 6) {      // bent stripes
        float x = uv.x + 0.06 * sin(uv.y * (8.0 + 10.0 * r1) + s) * (0.5 + length(uv - 0.5));
        float st = step(0.5, fract(x * (14.0 + 20.0 * r2)));
        float disc = step(length(uv - vec2(0.3 + 0.4 * r3, 0.5)), 0.25);
        st = abs(st - disc);
        c = mix(seedPalette(0.0, pk), seedPalette(1.0 + floor(r3 * 3.0), pk), st);
    } else if (style == 7) {      // hills and a sun
        c = mix(seedPalette(3.0, pk), seedPalette(1.0, pk), uv.y);
        vec2 sun = vec2(0.3 + 0.4 * r1, 0.55 + 0.2 * r2);
        c = mix(c, seedPalette(2.0, pk), 1.0 - smoothstep(0.09, 0.1, length((uv - sun) * vec2(1.0, 1.3))));
        for (int k = 0; k < 4; k++) {
            float hgt = 0.15 + 0.12 * float(3 - k) + 0.12 * fbm(vec2(uv.x * (2.0 + float(k)) + s + float(k) * 9.0, float(k)));
            c = mix(c, mix(seedPalette(4.0, pk), seedPalette(3.0, pk), float(k) * 0.22), step(uv.y, hgt));
        }
    } else if (style == 8) {      // dots
        float n = 18.0 + floor(r1 * 22.0);
        vec2 g = uv * n;
        vec2 f = fract(g) - 0.5;
        vec2 ctr = (floor(g) + 0.5) / n;
        float v = fbm(ctr * (2.0 + 3.0 * r2) + s);
        c = mix(seedPalette(0.0, pk), seedPalette(1.0 + floor(v * 3.0), pk),
                1.0 - smoothstep(0.42 * v - 0.03, 0.42 * v, length(f)));
    } else if (style == 9) {      // shapes
        vec2 p = uv - vec2(0.35 + 0.3 * r1, 0.6);
        c = mix(c, seedPalette(1.0, pk), 1.0 - smoothstep(0.24, 0.245, length(p)));
        vec2 q = uv - vec2(0.62, 0.32);
        c = mix(c, seedPalette(2.0, pk), step(abs(q.x) + 0.0, 0.17) * step(abs(q.y), 0.17));
        float tri = step(uv.y, 0.75 - 1.7 * abs(uv.x - 0.25 - 0.3 * r2)) * step(0.15, uv.y);
        c = mix(c, seedPalette(3.0, pk), tri * 0.95);
        c = mix(c, ink, step(abs(uv.y - 0.15), 0.008));
    } else if (style == 10) {     // a grid with a diagonal
        float n = 12.0 + floor(r1 * 20.0);
        vec2 id = floor(uv * n);
        float d = abs(id.x - (n - 1.0 - id.y));
        float v = exp(-d * (0.3 + r2)) + 0.6 * step(hash(id + s), 0.06 + 0.06 * r3) + 0.15 * hash(id + s + 1.0);
        v = clamp(v, 0.0, 1.0);
        c = v < 0.5 ? mix(seedPalette(4.0, pk), seedPalette(1.0, pk), v * 2.0)
                    : mix(seedPalette(1.0, pk), seedPalette(3.0, pk), v * 2.0 - 1.0);
        vec2 f = fract(uv * n);
        c *= 0.85 + 0.15 * step(0.06, min(f.x, f.y));
    } else if (style >= 12 && style <= 15) {
        // the newer styles share one palette, looked up once
        vec3 pal[5];
        for (int i = 0; i < 5; i++) pal[i] = seedPalette(float(i), pk);
        if (style == 12) {        // hard-edged stripes, side by side
            float n = 3.0 + floor(r1 * 6.0);
            int k = int(mod(floor(uv.x * n) + floor(r2 * 5.0), 5.0));
            c = pal[k];
            c = mix(c, pal[4], step(abs(fract(uv.x * n) - 0.5), 0.02 + 0.03 * r3) * step(0.5, r3));
        } else if (style == 13) { // squares nested, each in another colour
            vec2 q = abs(uv - vec2(0.5, 0.45 + 0.1 * r2));
            float d = max(q.x, q.y * (1.0 + 0.3 * r1));
            c = pal[int(min(4.0, floor(d * 8.0)))];
        } else if (style == 14) { // drips and splashes on a ground
            c = pal[0];
            for (int i = 1; i < 5; i++) {
                float fi = float(i);
                float x = h1(s + fi * 3.1);
                float w = 0.01 + 0.02 * h1(s + fi * 5.7);
                float drip = step(abs(uv.x - x - 0.03 * sin(uv.y * 9.0 + fi)), w)
                           * step(1.0 - uv.y, 0.5 + 0.5 * h1(s + fi * 9.3));
                float blot = step(noise(uv * (6.0 + fi * 2.0) + s + fi * 11.0), 0.3 + 0.07 * r2);
                c = mix(c, pal[i], max(drip, blot * step(0.4, h1(s + fi))));
            }
        } else {                  // a page of tokens: words as blocks, one lit
            float rows = 9.0 + floor(r1 * 8.0);
            float row = floor(uv.y * rows);
            float x = uv.x * (5.0 + 4.0 * r2) + h1(row + s) * 3.0;
            float word = floor(x);
            float inWord = step(0.12, fract(x)) * step(0.25, fract(uv.y * rows)) * step(fract(uv.y * rows), 0.8);
            float lit = step(0.93, hash(vec2(word, row) + s));
            c = mix(pal[0], lit > 0.5 ? pal[1] : pal[4],
                    inWord * step(0.08, uv.x) * step(uv.x, 0.92) * step(0.08, uv.y) * step(uv.y, 0.92));
        }
    } else {                      // noise in big pixels
        float n = 10.0 + floor(r1 * 30.0);
        vec2 ctr = (floor(uv * n) + 0.5) / n;
        float v = fbm(ctr * (1.5 + 3.0 * r2) + s * 1.3);
        c = seedPalette(floor(v * 5.0), pk);
    }
    // canvas grain, and a thin dark frame
    c *= 0.95 + 0.05 * noise(uv * 400.0);
    float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    return mix(vec3(0.05), c, step(0.012, edge));
}


// ---------------------------------------------------------------------------
// The city's traces: posters, tags, newspapers (designs from a seed)
// ---------------------------------------------------------------------------

vec3 posterColour(float k)
{
    const vec3 C[8] = vec3[](vec3(0.92, 0.18, 0.15), vec3(0.98, 0.82, 0.15), vec3(0.12, 0.30, 0.70),
                             vec3(0.08, 0.08, 0.09), vec3(0.95, 0.94, 0.90), vec3(0.15, 0.62, 0.42),
                             vec3(0.95, 0.45, 0.65), vec3(0.98, 0.55, 0.12));
    return C[int(mod(k, 8.0))];
}

// A poster: a coloured ground, a picture block, a big title and lines of
// small print; now and then torn at a corner.  Alpha 0 where it is gone.
vec4 poster(vec2 uv, float seed)
{
    float s = seed * 3.17;
    vec3 bg = posterColour(floor(h1(s) * 8.0));
    vec3 c = bg;
    vec3 ink = posterColour(floor(h1(s + 1.0) * 8.0));
    if (length(ink - bg) < 0.3) ink = vec3(1.0) - bg;
    // the picture: a disc, a band or a face-like oval
    float kind = h1(s + 2.0);
    vec2 pc = vec2(0.5, 0.62);
    if (kind < 0.33)      c = mix(c, posterColour(floor(h1(s + 3.0) * 8.0)), 1.0 - step(0.26, length(uv - pc)));
    else if (kind < 0.66) c = mix(c, posterColour(floor(h1(s + 3.0) * 8.0)), step(abs(uv.y - 0.62), 0.16));
    else                  c = mix(c, vec3(0.1), 1.0 - step(0.2, length((uv - pc) * vec2(1.0, 0.75))));
    // a title in big blocks, and lines of small print
    float title = step(abs(uv.y - 0.26), 0.055) * step(0.1, uv.x) * step(uv.x, 0.9)
                * step(0.25, fract(uv.x * (5.0 + floor(h1(s + 4.0) * 5.0))));
    c = mix(c, ink, title);
    float small = step(abs(uv.y - 0.12), 0.035) * step(0.15, uv.x) * step(uv.x, 0.85)
                * step(0.5, fract(uv.y * 60.0)) * step(0.3, fract(uv.x * 23.0));
    c = mix(c, ink, small * 0.8);
    // weather and age
    c *= 0.82 + 0.18 * noise(uv * 25.0 + s);
    float a = 1.0;
    if (h1(s + 5.0) < 0.35) {          // torn off from a corner
        vec2 corner = vec2(step(0.5, h1(s + 6.0)), step(0.5, h1(s + 7.0)));
        float tear = length(uv - corner) - 0.25 - 0.25 * h1(s + 8.0) - 0.08 * noise(uv * 18.0 + s);
        a = step(0.0, tear);
    }
    return vec4(c, a);
}

// A tag sprayed on a wall: fat letters made of noise, a dark outline, a
// light shine, a drip or two; see-through elsewhere
vec4 graffiti(vec2 uv, float seed)
{
    float s = seed * 5.31;
    vec3 fill = posterColour(floor(h1(s) * 8.0));
    vec3 line = h1(s + 1.0) < 0.5 ? vec3(0.04) : posterColour(floor(h1(s + 2.0) * 8.0));
    float n = 3.0 + floor(h1(s + 3.0) * 4.0);             // letters
    float lx = uv.x * n;
    float cell = floor(lx);
    vec2 q = vec2(fract(lx) - 0.5, (uv.y - 0.5) * 1.6);
    q.x += 0.15 * q.y * (h1(s + 4.0) - 0.3);             // leaning
    float d = 1.0;
    // each letter: two or three strokes with bulges
    for (int k = 0; k < 3; k++) {
        float r = h1(s + cell * 7.0 + float(k));
        vec2 a = vec2(r - 0.5, -0.5) * vec2(0.6, 1.0);
        vec2 b = vec2(h1(s + cell * 11.0 + float(k)) - 0.5, 0.5) * vec2(0.6, 1.0);
        if (k == 2) { a = vec2(-0.3, h1(s + cell) - 0.5); b = vec2(0.3, a.y); }
        vec2 pa = q - a, ba = b - a;
        float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        d = min(d, length(pa - ba * t) - 0.13 - 0.04 * noise(uv * 20.0 + s));
    }
    float body = step(d, 0.0);
    float outline = step(d, 0.045) - body;
    // drips under the letters
    float drip = step(fract(uv.x * 37.0 + s), 0.08) * step(0.12, uv.y) * step(uv.y, 0.35)
               * step(h1(floor(uv.x * 37.0 + s) + s), 0.25);
    vec3 c = mix(line, fill, body);
    c = mix(c, vec3(1.0), body * step(0.6, noise(uv * vec2(40.0, 10.0) + s)) * 0.5);
    float a = max(body + outline, drip * (1.0 - body));
    if (drip > 0.5 && body < 0.5) c = fill * 0.8;
    return vec4(c, clamp(a, 0.0, 1.0) * (0.85 + 0.15 * noise(uv * 60.0)));
}

// A sheet of newspaper: off-white, columns of grey print, a headline
vec3 newspaper(vec2 uv)
{
    vec3 c = vec3(0.86, 0.85, 0.80);
    float col = step(0.06, fract(uv.x * 3.0)) * step(fract(uv.x * 3.0), 0.94);
    float print = step(0.5, fract(uv.y * 45.0)) * col * step(uv.y, 0.78);
    c = mix(c, vec3(0.45), print * 0.6);
    c = mix(c, vec3(0.1), step(0.83, uv.y) * step(uv.y, 0.93) * step(0.08, uv.x) * step(uv.x, 0.92));
    return c;
}


// Moving light on a surface, by pattern (seed) and time; .a is how much
// light there is (the surface behind shows where it is dark)
vec4 lightShow(vec2 uv, float seed, float t)
{
    float scene = floor(t / 12.0) + seed;
    int k = int(mod(scene, 6.0));
    float f = fract(t / 12.0);
    vec3 c = vec3(0.0);
    if (k == 0) {             // colour rising in waves
        float w = sin((uv.y * 6.0 - t * 1.5) * 3.14159 + sin(uv.x * 9.0 + t) * 0.8);
        c = mix(vec3(0.1, 0.2, 1.0), vec3(1.0, 0.2, 0.6), uv.y) * smoothstep(0.2, 0.9, w);
    } else if (k == 1) {      // three colours sweeping across
        float x = fract(uv.x - t * 0.15);
        c = x < 0.33 ? vec3(0.1, 0.25, 1.0) : x < 0.66 ? vec3(1.0) : vec3(1.0, 0.1, 0.12);
        c *= 0.8 + 0.2 * sin(uv.y * 40.0 + t * 4.0);
    } else if (k == 2) {      // stars falling
        vec2 g = vec2(uv.x * 24.0, uv.y * 12.0 + t * 3.0);
        vec2 id = floor(g), q = fract(g) - 0.5;
        float r = hash(id + seed);
        c = vec3(1.0, 0.9, 0.6) * step(0.75, r) * smoothstep(0.25, 0.0, length(q));
    } else if (k == 3) {      // a canvas from a seed, fading in and out
        c = seeded(uv, scene * 17.0 + 3.0) * smoothstep(0.0, 0.15, f) * smoothstep(1.0, 0.85, f);
    } else if (k == 4) {      // rings from the middle
        float d = length((uv - 0.5) * vec2(2.0, 1.0));
        c = 0.5 + 0.5 * cos(vec3(0.0, 2.0, 4.0) + d * 14.0 - t * 3.0);
        c *= smoothstep(0.0, 0.3, sin(d * 30.0 - t * 5.0));
    } else {                  // the windows lit one by one
        vec2 id = floor(uv * vec2(14.0, 6.0));
        float on = step(0.5, fract(hash(id + seed) + t * 0.4));
        c = mix(vec3(1.0, 0.75, 0.3), vec3(0.3, 0.6, 1.0), hash(id + 7.0)) * on
          * step(0.15, fract(uv.x * 14.0)) * step(0.2, fract(uv.y * 6.0));
    }
    float a = clamp(max(c.r, max(c.g, c.b)) * 1.3, 0.0, 1.0);
    return vec4(c, a);
}

// A drawing on paper under a white mount: ink contours, a quick figure,
// or a sketch of a street in perspective, from a seed
vec3 drawing(vec2 uv, float seed)
{
    float s = seed * 1.37;
    int kind = int(mod(seed, 3.0));
    vec2 p = (uv - 0.15) / 0.7;                       // inside the mount
    float inPaper = step(0.0, p.x) * step(p.x, 1.0) * step(0.0, p.y) * step(p.y, 1.0);
    vec3 paper = vec3(0.95, 0.93, 0.86);
    float ink = 0.0;
    if (kind == 0) {          // contours round a few hills of noise
        float v = fbm(p * 2.5 + s);
        ink = 1.0 - smoothstep(0.0, 0.08, abs(fract(v * 9.0) - 0.5) * 2.0 - 0.75);
    } else if (kind == 1) {   // a figure in a few strokes
        vec2 q = p - vec2(0.5, 0.0);
        float head = abs(length(q - vec2(0.0, 0.78)) - 0.09);
        float body = abs(q.x - 0.04 * sin(q.y * 12.0 + s)) + step(0.7, q.y) + step(q.y, 0.3);
        float legs = min(abs(q.x - 0.25 * (0.3 - q.y)), abs(q.x + 0.25 * (0.3 - q.y))) + step(0.3, q.y);
        float arms = abs(q.y - 0.58 - 0.4 * abs(q.x)) + step(0.28, abs(q.x));
        ink = step(min(min(head, body), min(legs, arms)), 0.012);
    } else {                  // a street in perspective, hatched
        vec2 q = p - vec2(0.5, 0.45);
        float rays = abs(fract(atan(q.y, q.x) * 4.0 / 3.14159 + h1(s)) - 0.5);
        float hatch = step(0.85, fract((p.x + p.y) * 40.0)) * step(0.5, fbm(p * 4.0 + s));
        ink = max(step(rays, 0.02) * step(0.15, length(q)), hatch * 0.7);
    }
    vec3 c = mix(paper, vec3(0.1, 0.1, 0.12), ink * inPaper * (0.75 + 0.25 * noise(uv * 90.0)));
    c = mix(vec3(0.97), c, inPaper);                  // the white mount
    float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    return mix(vec3(0.08), c, step(0.02, edge));      // a thin black frame
}

struct Surface { vec3 albedo; float spec; float gloss; vec3 emissive; float wrap; };

vec3 glass(vec3 N, vec3 V, float variation)
{
    vec3 R = reflect(-V, N);
    float fres = 0.10 + 0.5 * pow(1.0 - max(dot(N, V), 0.0), 4.0);
    vec3 inside = mix(vec3(0.05, 0.05, 0.05), vec3(0.22, 0.18, 0.14), variation * variation);
    vec3 refl = mix(vec3(0.55, 0.57, 0.6), skyColor(R), 0.5) * 0.7;
    return mix(inside, refl, fres);
}

vec3 unpackColour(float pk)
{
    float c = floor(pk - 1.0 + 0.5);
    return vec3(floor(c / 1024.0), mod(floor(c / 32.0), 32.0), mod(c, 32.0)) / 31.0;
}

Surface glassWall(vec2 uv, float h, vec3 tint, vec3 N, vec3 V)
{
    // Curtain wall: glass panes in a slim metal grid, offices lit at night
    vec2 fw = fwidth(uv);
    vec2 cell = floor(uv * vec2(2.0, 1.0));
    float frame = max(fpulse(0.0, 0.06, uv.x * 2.0, fw.x * 2.0), fpulse(0.0, 0.08, uv.y, fw.y));
    vec3 g = glass(N, V, 0.2 + 0.3 * hash(cell + h));
    vec3 c = mix(toLinear(g) * mix(vec3(1.0), tint * 1.4, 0.35), toLinear(tint * 0.5 + 0.12), frame);
    Surface s = Surface(c, 0.9 * (1.0 - frame), 120.0, vec3(0), 0.0);
    if (uNight > 0.01) {
        float on = step(0.45, hash(cell * 1.7 + h * 13.0));
        s.emissive = toLinear(vec3(0.95, 0.92, 0.85)) * 0.9 * on * (1.0 - frame) * uNight;
    }
    return s;
}

Surface wall(vec2 uv, float seed, vec3 N, vec3 V)
{
    Surface s = Surface(vec3(0), 0.0, 16.0, vec3(0), 0.0);
    float style, h;
    bool coloured = false;
    vec3 custom = vec3(0.0);
    if (seed > 99.5) {
        // 100 + style * 40000 + packed OSM facade colour
        float c = seed - 100.0;
        style = floor(c / 40000.0 + 0.0001);
        float pk = c - style * 40000.0;
        coloured = pk > 0.5;
        if (coloured) custom = unpackColour(pk);
        h = fract(pk * 0.6180339 + style * 0.137);
    } else {
        style = floor(seed);
        h = fract(seed);
    }
    if (style > 3.5)
        return glassWall(uv, h, coloured ? custom : vec3(0.45, 0.5, 0.55), N, V);
    vec3 stone = coloured ? custom
               : mix(vec3(0.78, 0.72, 0.60), vec3(0.87, 0.82, 0.71), h);
    stone *= 0.92 + 0.12 * hash(vec2(h * 91.3, 7.1));
    // weathering: darker towards the street
    stone *= 0.88 + 0.12 * smoothstep(0.0, 2.0, uv.y);
    s.albedo = toLinear(stone);

    if (style > 2.5) {
        // Boat: dark painted hull, light cabin with a band of windows
        vec2 fwb = fwidth(uv);
        float hullTop = -4.9;
        float k = hash(vec2(h * 37.0, 2.0));
        vec3 hull = k < 0.3 ? vec3(0.06, 0.07, 0.09) : k < 0.55 ? vec3(0.08, 0.12, 0.22)
                  : k < 0.8 ? vec3(0.10, 0.18, 0.12) : vec3(0.35, 0.07, 0.06);
        vec3 cabin = mix(vec3(0.86, 0.84, 0.78), vec3(0.62, 0.45, 0.30), step(0.6, h));
        float isHull = 1.0 - smoothstep(hullTop - 0.03, hullTop + 0.03, vWorld.y);
        float win = uv.x < 0.0 ? 0.0 : fpulse(0.15, 0.85, uv.x * 2.0, fwb.x * 2.0)
                  * (smoothstep(-4.4, -4.35, vWorld.y) - smoothstep(-3.75, -3.7, vWorld.y));
        vec3 c = mix(cabin, vec3(0.08, 0.09, 0.10), win);
        s.albedo = toLinear(mix(c, hull, isHull));
        s.emissive = toLinear(vec3(1.0, 0.75, 0.45)) * 1.3 * win * uNight * step(0.3, hash(vec2(floor(uv.x * 2.0), h)));
        return s;
    }
    if (uv.x < 0.0 || style > 1.5)
        return s;

    vec2 fw = fwidth(uv);

    if (style > 0.5) {   // monument: tall narrow windows, floodlit at night
        float win = fpulse(0.42, 0.58, uv.x * 0.5, fw.x * 0.5)
                  * fpulse(0.15, 0.85, uv.y / 3.0, fw.y / 3.0);
        s.albedo = mix(s.albedo, toLinear(vec3(0.10, 0.10, 0.12)), win * 0.9);
        s.emissive = toLinear(vec3(1.0, 0.85, 0.6)) * 0.3 * (1.0 - win * 0.8)
                   * smoothstep(0.0, 1.0, 1.2 - uv.y / 12.0) * uNight;
        return s;
    }

    float floorIdx = floor(uv.y);
    vec2 cell = floor(uv);
    float r = hash(cell + h * 17.0);
    float ground = 1.0 - step(1.0, uv.y);

    // Upper-floor windows (French windows) and ground-floor shop fronts
    float win  = fpulse(0.32, 0.68, uv.x, fw.x) * fpulse(0.10, 0.86, uv.y, fw.y);
    float shop = fpulse(0.08, 0.92, uv.x, fw.x) * fpulse(0.0, 0.78, uv.y, fw.y);
    float w = mix(win, shop, ground);

    // Window surround (slightly lighter carved stone)
    float frame = fpulse(0.28, 0.72, uv.x, fw.x) * fpulse(0.06, 0.92, uv.y, fw.y) * (1.0 - ground);
    vec3 c = mix(stone, stone * 1.08, frame);

    // String course between floors
    c *= 1.0 - 0.22 * fpulse(0.0, 0.04, uv.y, fw.y);

    vec3 g = glass(N, V, r);
    // Shop fronts: dark with occasional coloured fascia
    // Shop fronts: dark glazing with a painted fascia in classic colours
    float k = hash(cell + 3.0);
    vec3 fascia = k < 0.25 ? vec3(0.10, 0.22, 0.16)      // bottle green
                : k < 0.5  ? vec3(0.32, 0.08, 0.09)      // bordeaux
                : k < 0.75 ? vec3(0.10, 0.13, 0.24)      // navy
                :            vec3(0.08, 0.08, 0.08);     // black
    vec3 shopColor = mix(vec3(0.06, 0.06, 0.065), fascia,
                         step(0.45, r) * fpulse(0.64, 0.78, uv.y, fw.y));
    // Window joinery: central mullion and transom, painted off-white
    float joinery = clamp(fpulse(0.49, 0.51, uv.x, fw.x)
                        + fpulse(0.66, 0.685, uv.y, fw.y), 0.0, 1.0) * (1.0 - ground);
    vec3 pane = mix(pow(g, vec3(1.0 / 2.2)), vec3(0.85, 0.84, 0.80), joinery * 0.8);
    vec3 opening = mix(pane, shopColor, ground);
    c = mix(c, opening, w);

    // Wrought-iron balconies on the 2nd and 5th floors (continuous),
    // small ones elsewhere
    float cont = (abs(floorIdx - 2.0) < 0.5 || abs(floorIdx - 5.0) < 0.5) ? 1.0 : 0.0;
    float rail = fpulse(0.12, 0.30, uv.y, fw.y) * (1.0 - ground);
    float bars = fpulse(0.0, 0.25, uv.x * 12.0, fw.x * 12.0);
    float topBar = fpulse(0.27, 0.30, uv.y, fw.y);
    float small = fpulse(0.25, 0.75, uv.x, fw.x) * step(0.55, hash(vec2(floorIdx, h * 13.0)));
    float balcony = rail * max(small, cont) * clamp(bars + topBar * 4.0, 0.0, 1.0);
    c = mix(c, vec3(0.06, 0.06, 0.065), balcony * 0.85);

    // Fade the detail out when it is too small on screen
    float detail = 1.0 - smoothstep(0.35, 0.8, max(fw.x, fw.y));
    vec3 average = mix(stone * 0.8, vec3(0.2), 0.25);
    c = mix(average, c, detail);

    // At night some windows are lit (warm, varied), most shops too
    if (uNight > 0.01) {
        float lr = hash(cell * 1.37 + h * 29.0);
        float on = ground > 0.5 ? step(0.5, lr) : step(0.6, lr);
        float tint = hash(cell + 9.1);
        vec3 warm = tint < 0.85 ? mix(vec3(1.0, 0.55, 0.25), vec3(1.0, 0.80, 0.55), tint / 0.85)
                                : vec3(0.75, 0.82, 1.0);          // the odd cool LED / TV
        float fy = fract(uv.y);
        // light falls off towards the window sill; curtains dim some windows
        float glow = ground > 0.5 ? 0.9 * (0.6 + 0.6 * fy)
                   : (0.45 + 0.6 * hash(cell + 4.2)) * (0.55 + 0.6 * fy);
        float paneMask = w * (1.0 - joinery * 0.9) * (1.0 - balcony * 0.7);
        vec3 lit = toLinear(warm) * glow * on * paneMask;
        vec3 avgLit = toLinear(vec3(1.0, 0.72, 0.45)) * 0.09;
        s.emissive = mix(avgLit, lit, detail) * uNight;
    }

    s.albedo = toLinear(c);
    s.spec = w * 0.5 * detail * (1.0 - ground);
    s.gloss = 64.0;
    return s;
}

Surface mansard(vec2 uv, float seed, vec3 N, vec3 V)
{
    Surface s = Surface(vec3(0), 0.15, 24.0, vec3(0), 0.0);
    vec2 fw = fwidth(uv);
    vec3 zinc = mix(vec3(0.40, 0.44, 0.49), vec3(0.50, 0.53, 0.57), fract(seed * 7.0));
    float seams = fpulse(0.0, 0.08, uv.x * 6.0, fw.x * 6.0);
    vec3 c = zinc * (1.0 - 0.15 * seams);
    if (uv.x >= 0.0) {
        float dormer = fpulse(0.30, 0.70, uv.x, fw.x) * fpulse(0.10, 0.80, uv.y, fw.y);
        float pane   = fpulse(0.37, 0.63, uv.x, fw.x) * fpulse(0.18, 0.70, uv.y, fw.y);
        vec3 g = pow(glass(N, V, hash(floor(uv) + 5.0)), vec3(1.0 / 2.2));
        c = mix(c, vec3(0.86, 0.82, 0.74), dormer);
        c = mix(c, g, pane);
        float detail = 1.0 - smoothstep(0.35, 0.8, max(fw.x, fw.y));
        c = mix(zinc * 0.95, c, detail);
        if (uNight > 0.01) {
            vec2 cell = floor(uv);
            float on = step(0.6, hash(cell * 2.11 + seed * 31.0));
            vec3 lit = toLinear(vec3(1.0, 0.75, 0.45)) * 1.2 * on * pane;
            s.emissive = mix(toLinear(vec3(1.0, 0.75, 0.45)) * 0.08, lit, detail) * uNight;
        }
    }
    s.albedo = toLinear(c);
    return s;
}

Surface quay(vec2 uv, float seed)
{
    // Limestone blocks in staggered courses, darker and greener near water
    vec2 fw = fwidth(uv);
    float row = floor(uv.y / 0.55);
    float u = uv.x / 1.3 + 0.5 * mod(row, 2.0);
    float joints = max(fpulse(0.0, 0.05, u, fw.x / 1.3), fpulse(0.0, 0.07, uv.y / 0.55, fw.y / 0.55));
    vec3 c = vec3(0.76, 0.71, 0.61) * (0.88 + 0.16 * hash(vec2(floor(u), row) + seed));
    c *= 0.9 + 0.15 * noise(uv * 3.0);
    c = mix(c, vec3(0.45, 0.42, 0.36), joints * 0.6);
    float wet = smoothstep(-3.5, -5.8, vWorld.y);
    c = mix(c, vec3(0.30, 0.32, 0.24), wet * 0.7);
    return Surface(toLinear(c), 0.0, 16.0, vec3(0), 0.0);
}

Surface ground(int m, vec2 p, float seed)
{
    Surface s = Surface(vec3(0), 0.0, 16.0, vec3(0), 0.0);
    vec3 c;
    float n = noise(p * 1.7);
    if (m == 0) {          // pavement / sidewalk
        float slabs = fpulse(0.0, 0.04, p.x * 0.8, fwidth(p.x) * 0.8)
                    + fpulse(0.0, 0.04, p.y * 0.8, fwidth(p.y) * 0.8);
        c = vec3(0.60, 0.58, 0.55) * (0.92 + 0.12 * n) * (1.0 - 0.12 * clamp(slabs, 0.0, 1.0));
    } else if (m == 1) {   // asphalt
        c = vec3(0.19, 0.19, 0.20) * (0.85 + 0.3 * fbm(p * 0.7));
        s.spec = 0.05;
    } else if (m == 2) {   // curb stone
        c = vec3(0.66, 0.65, 0.62);
    } else if (m == 3) {   // sand path
        c = vec3(0.80, 0.74, 0.60) * (0.9 + 0.12 * n);
    } else if (m == 4) {   // grass
        c = vec3(0.24, 0.40, 0.13) * (0.72 + 0.5 * fbm(p * 0.35));
    } else if (m == 5) {   // park gravel (Luxembourg)
        c = vec3(0.83, 0.77, 0.63) * (0.9 + 0.12 * fbm(p * 0.9));
    } else if (m == 7) {   // wood / shrubs
        c = vec3(0.13, 0.25, 0.08) * (0.65 + 0.7 * fbm(p * 0.4));
    } else if (m == 8) {   // paved square, cobbles
        float cob = noise(p * 5.0);
        c = vec3(0.58, 0.56, 0.52) * (0.85 + 0.2 * cob);
    } else if (m == 9) {   // parking
        c = vec3(0.30, 0.30, 0.31) * (0.9 + 0.2 * n);
    } else if (m == 21) {  // road paint, a little worn
        c = vec3(0.86, 0.86, 0.83) * (0.75 + 0.3 * noise(p * 4.0 + seed * 50.0));
        c = mix(vec3(0.22), c, smoothstep(0.15, 0.45, noise(p * 2.3 + seed * 13.0)) * 0.6 + 0.4);
    } else if (m == 20) {  // flowerbed
        float f = step(0.62, noise(p * 3.0));
        vec3 flower = mix(vec3(0.75, 0.15, 0.20), vec3(0.85, 0.75, 0.25), step(0.5, hash(floor(p * 3.0))));
        c = mix(vec3(0.20, 0.33, 0.10) * (0.8 + 0.4 * n), flower, f);
    } else {
        c = vec3(1.0, 0.0, 1.0);
    }
    s.albedo = toLinear(c);
    return s;
}

// --------------------------------------------------------------- shadows ---

float shadowFactor(vec3 N, vec3 L)
{
    if (uShadows == 0) return 1.0;
    vec3 p = vShadowPos.xyz / vShadowPos.w * 0.5 + 0.5;
    if (p.x <= 0.0 || p.x >= 1.0 || p.y <= 0.0 || p.y >= 1.0 || p.z >= 1.0)
        return 1.0;
    float bias = 0.0006 + 0.0015 * (1.0 - max(dot(N, L), 0.0));
    float sum = 0.0;
    vec2 texel = 1.0 / vec2(textureSize(uShadowMap, 0));
    for (int x = -1; x <= 1; x++)
        for (int y = -1; y <= 1; y++)
            sum += texture(uShadowMap, vec3(p.xy + vec2(x, y) * texel, p.z - bias));
    return sum / 9.0;
}

// ---------------------------------------------------------- local lights ---

// Diffuse light from the street lamps and headlights.  With gloss > 0 a
// mirror-like highlight is added (wet streets reflect the lamps), returned
// separately in 'specular'.
vec3 localLightSpec(vec3 N, vec3 V, float gloss, out vec3 specular)
{
    specular = vec3(0.0);
    if (uNight < 0.01) return vec3(0.0);
    vec3 sum = vec3(0.0);
    vec3 lampColor = vec3(1.0, 0.62, 0.30);
    for (int i = 0; i < uLightCount; i++) {
        vec3 d = uLights[i].xyz - vWorld;
        float d2 = dot(d, d);
        float reach = gloss > 0.0 ? 6400.0 : 900.0;
        if (d2 < reach) {
            float dist = sqrt(d2);
            vec3 L = d / dist;
            float ndl = max(dot(N, L), 0.0) * 0.8 + 0.2;
            float att = uLights[i].w / (1.0 + 0.12 * d2) * (1.0 - smoothstep(18.0, 30.0, dist));
            sum += lampColor * att * ndl;
            if (gloss > 0.0) {
                vec3 H = normalize(L + V);
                float sp = pow(max(dot(N, H), 0.0), gloss);
                specular += lampColor * sp * 0.6 / (1.0 + 0.006 * d2);
            }
        }
    }
    // Headlights: a soft cone in front of the car
    if (uHeadOn > 0.0) {
        vec3 d = vWorld - uHeadPos;
        float dist = length(d);
        float cosA = dot(d / max(dist, 0.01), uHeadDir);
        float cone = smoothstep(0.82, 0.95, cosA);
        float att = 26.0 / (1.0 + 0.05 * dist * dist) * (1.0 - smoothstep(40.0, 70.0, dist));
        float ndl = max(dot(N, -d / max(dist, 0.01)), 0.0);
        sum += vec3(1.0, 0.95, 0.85) * cone * att * ndl * uHeadOn;
    }
    specular *= uNight;
    return sum * uNight;
}

vec3 localLight(vec3 N)
{
    vec3 unused;
    return localLightSpec(N, vec3(0.0, 1.0, 0.0), 0.0, unused);
}

// Traffic light lamp: seed = 0 red, 1 amber, 2 green; uv = (offset, group).
// Same timing as Road_Network.Signal_State.
float signalOn(float lamp, float offset, float group)
{
    float p = mod(uTime + offset, 32.0);
    float state;   // 0 green, 1 amber, 2 red
    if (group < 0.5) state = p < 13.0 ? 0.0 : p < 16.0 ? 1.0 : 2.0;
    else             state = p < 16.0 ? 2.0 : p < 29.0 ? 0.0 : 1.0;
    return abs((2.0 - lamp) - state) < 0.5 ? 1.0 : 0.0;
}

vec3 roofColour(vec3 fallback)
{
    // packed 5-5-5 colour in vUV.y (0 = none)
    if (vUV.y < 0.5) return fallback;
    float c = floor(vUV.y - 1.0 + 0.5);
    vec3 rgb = vec3(floor(c / 1024.0), mod(floor(c / 32.0), 32.0), mod(c, 32.0)) / 31.0;
    return rgb * (0.85 + 0.15 * fbm(vWorld.xz * 0.2));
}

// How much of the haze lies between the eye and p: the usual haze (more
// on a hot day), and the morning mist, thick on the water and thinning
// above it (the density falls by e every 4 m: integrated along the ray)
float fogAt(vec3 p)
{
    float d = length(uCamPos - p);
    float f = 1.0 - exp(-d * uFogDensity * (1.0 + 0.9 * uHeat));
    if (uMist > 0.0) {
        float H = 4.0;
        float y0 = max(uCamPos.y - uMistY, 0.0);
        float y1 = max(p.y - uMistY, 0.0);
        float dy = y1 - y0;
        float avg = abs(dy) > 0.05 ? H * (exp(-y0 / H) - exp(-y1 / H)) / dy : exp(-y0 / H);
        float dens = uMist * (0.0025 + 0.05 * avg);
        f = 1.0 - (1.0 - f) * exp(-d * dens);
    }
    return f;
}

// The colour of the haze: the sky at the horizon, whiter in the mist
vec3 fogColour()
{
    vec3 c = toLinear(uSkyHorizon);
    return mix(c, vec3(dot(c, vec3(0.3, 0.5, 0.2))) * 1.08, 0.6 * uMist);
}

// ------------------------------------------------------------------ main ---

void main()
{
    if (uEraseN > 0 && erased(vWorld)) discard;
    int m = int(vMat + 0.5);
    vec3 N = normalize(vNormal);
    vec3 V = normalize(uCamPos - vWorld);
    vec3 L = normalize(uSunDir);

    Surface s;
    if (m == 6) {
        // Water: animated normal, sky reflection, sun glint
        vec2 p = vWorld.xz;
        float e = 0.15;
        float t = uTime * 0.6;
        float h0 = fbm(p * 0.25 + vec2(t, t * 0.7));
        float hx = fbm((p + vec2(e, 0)) * 0.25 + vec2(t, t * 0.7));
        float hz = fbm((p + vec2(0, e)) * 0.25 + vec2(t, t * 0.7));
        vec3 wn = normalize(vec3(-(hx - h0) / e * 0.6, 1.0, -(hz - h0) / e * 0.6));
        vec3 R = reflect(-V, wn);
        float fres = 0.04 + 0.96 * pow(1.0 - max(dot(wn, V), 0.0), 5.0);
        vec3 deep = toLinear(vec3(0.10, 0.20, 0.21)) * (uAmbSky.b * 2.2 + 0.02);
        vec3 col = mix(deep, toLinear(skyColor(R)), fres * 0.8);
        col += uSunColor * pow(max(dot(R, L), 0.0), 300.0) * 2.0 * shadowFactor(N, L);
        col += localLight(wn) * (0.08 + 0.5 * fres) * (0.7 + 0.6 * h0);   // lamps on the water
        col = mix(col, fogColour(), fogAt(vWorld));
        col = col / (1.0 + col) * 1.25;
        if (uEra > 0.5) col = kodachrome(col);
        fragColor = vec4(pow(col, vec3(1.0 / 2.2)), 1.0);
        return;
    } else if (m == 10) {
        s = wall(vUV, vSeed, N, V);
    } else if (m == 11) {
        s = mansard(vUV, vSeed, N, V);
    } else if (m == 12) {
        vec3 zinc = roofColour(vec3(0.36, 0.38, 0.41) * (0.8 + 0.25 * fbm(vWorld.xz * 0.15)))
                  * (1.0 - 0.12 * fpulse(0.0, 0.08, vWorld.x * 1.6, fwidth(vWorld.x) * 1.6));
        s = Surface(toLinear(zinc), 0.1, 16.0, vec3(0), 0.0);
    } else if (m == 13) {
        s = Surface(toLinear(vec3(0.30, 0.25, 0.20)), 0.0, 8.0, vec3(0), 0.0);
    } else if (m == 14) {
        vec3 leaf = mix(vec3(0.17, 0.30, 0.08), vec3(0.32, 0.45, 0.13), vSeed);
        float n = noise(vWorld.xy * 1.3 + vWorld.zy * 0.9);
        leaf *= 0.65 + 0.6 * n;
        // autumn: each tree turns in its own time and its own colour
        if (uAutumn > 0.0) {
            float k = fract(vSeed * 7.31);
            vec3 fall = k < 0.4 ? vec3(0.78, 0.55, 0.10) : k < 0.7 ? vec3(0.72, 0.33, 0.07)
                      : k < 0.9 ? vec3(0.55, 0.36, 0.12) : vec3(0.60, 0.15, 0.06);
            fall *= 0.7 + 0.5 * n;
            float turn = clamp(uAutumn * 1.4 - k * 0.6 + 0.15 * (n - 0.5), 0.0, 1.0);
            leaf = mix(leaf, fall, turn);
        }
        // spring: one tree in four flowers, cherries pink, chestnuts white
        if (uBlossom > 0.0) {
            float k = fract(vSeed * 3.17);
            if (k < 0.25) {
                float b = noise(vWorld.xy * 4.1 + vWorld.zy * 3.7 + vSeed * 9.0);
                vec3 flower = k < 0.12 ? vec3(0.97, 0.74, 0.82) : vec3(0.96, 0.95, 0.9);
                leaf = mix(leaf, flower * (0.85 + 0.2 * n), smoothstep(0.62 - 0.5 * uBlossom, 0.72 - 0.5 * uBlossom, b));
            }
        }
        // winter: the crown thins out to bare twigs
        if (uBare > 0.0) {
            float holes = noise(vWorld.xy * 2.3 + vWorld.zy * 1.9 + vSeed * 13.0);
            float keep = smoothstep(uBare - 0.1, uBare + 0.1, holes);
            // a fake network of twigs where the leaves have gone
            float twig = 1.0 - smoothstep(0.0, 0.05,
                abs(noise(vWorld.xy * 3.1 + vWorld.zy * 2.7 + 5.0) - 0.5));
            leaf = mix(vec3(0.22, 0.18, 0.14) * (0.8 + 0.3 * n), leaf, keep);
            gAlpha = max(keep, 0.9 * twig);
        }
        s = Surface(toLinear(leaf), 0.0, 8.0, vec3(0), 0.45);
        // Christmas: strings of little lights in the street trees
        if (uXmas > 0.5 && uNight > 0.05) {
            vec3 q = floor(vWorld / 0.55);
            float h = hash(vec2(dot(q, vec3(1.0, 31.0, 97.0)) * 0.017, 3.7));
            vec3 f = fract(vWorld / 0.55) - 0.5;
            if (h > 0.74 && length(f) < 0.24) {
                float tw = 0.65 + 0.35 * sin(uTime * 1.7 + h * 60.0);
                s.emissive = toLinear(vec3(1.0, 0.85, 0.55)) * 3.0 * tw * uNight;
            }
        }
    } else if (m == 37) {          // Christmas tree: fir, baubles by day, lights at night
        vec3 fir = vec3(0.07, 0.20, 0.10) * (0.7 + 0.5 * noise(vWorld.xz * 3.0 + vWorld.y * 2.0));
        s = Surface(toLinear(fir), 0.05, 10.0, vec3(0), 0.4);
        vec3 q = floor(vWorld / 0.6);
        float h = hash(vec2(dot(q, vec3(1.0, 31.0, 97.0)) * 0.013, 9.1));
        vec3 f = fract(vWorld / 0.6) - 0.5;
        float dotMask = step(length(f), 0.24);
        if (h > 0.6 && dotMask > 0.0) {
            float k = fract(h * 13.0);
            vec3 c = k < 0.4 ? vec3(1.0, 0.82, 0.45) : k < 0.6 ? vec3(1.0, 0.15, 0.1)
                   : k < 0.8 ? vec3(0.95, 0.75, 0.2) : vec3(0.3, 0.5, 1.0);
            float tw = 0.55 + 0.45 * sin(uTime * 2.3 + h * 80.0);
            s.albedo = toLinear(c) * 0.6;          // baubles
            s.spec = 0.8;
            s.gloss = 60.0;
            s.emissive = toLinear(c) * 3.5 * tw * uNight;
        }
    } else if (m == 39) {          // white fur: Father Christmas's beard and trim
        float n = noise(vWorld.xy * 40.0 + vWorld.zy * 37.0);
        s = Surface(toLinear(vec3(0.93, 0.92, 0.9) * (0.85 + 0.15 * n)), 0.0, 6.0, vec3(0), 0.5);
    } else if (m == 40) {          // pumpkin skin with ribs
        float rib = 0.85 + 0.15 * abs(sin(atan(vWorld.x - floor(vWorld.x * 2.0) * 0.5,
                                                vWorld.z - floor(vWorld.z * 2.0) * 0.5) * 4.0));
        vec3 c = vec3(0.92, 0.42, 0.06) * rib * (0.85 + 0.2 * noise(vWorld.xz * 9.0 + vWorld.y * 5.0));
        s = Surface(toLinear(c), 0.25, 24.0, vec3(0), 0.2);
    } else if (m == 41) {          // the carved face: a candle inside at night
        float flicker = 0.75 + 0.15 * sin(uTime * 13.0 + vWorld.x * 7.0)
                      + 0.1 * sin(uTime * 23.0 + vWorld.z * 5.0);
        s = Surface(toLinear(vec3(0.12, 0.05, 0.01)), 0.0, 8.0,
                    toLinear(vec3(1.0, 0.6, 0.15)) * 4.0 * flicker * uNight, 0.0);
    } else if (m == 42) {          // a ghost's sheet: pale, glowing, see-through
        s = Surface(toLinear(vec3(0.88, 0.92, 0.98)), 0.1, 12.0,
                    toLinear(vec3(0.6, 0.7, 0.85)) * 1.1 * uNight, 0.5);
        gAlpha = 0.65;
    } else if (m == 43) {          // the Little Prince's asteroid
        vec3 c = vec3(0.85, 0.72, 0.5) * (0.75 + 0.35 * noise(vWorld.xz * 0.2 + vWorld.y * 0.15));
        s = Surface(toLinear(c), 0.0, 8.0, toLinear(vec3(1.0, 0.85, 0.6)) * 0.6 * uNight, 0.4);
    } else if (m == 44) {          // a painting in the Louvre
        int id = int(vSeed + 0.5);
        vec2 uv = clamp(vUV, 0.0, 1.0);
        vec3 c = id == 0 ? monaLisa(uv) : id == 1 ? liberty(uv) : id == 2 ? medusa(uv)
               : id == 3 ? coronation(uv) : stillLife(uv);
        s = Surface(toLinear(c), 0.15, 30.0, vec3(0), 0.0);
    } else if (m == 45) {          // marble
        float n = noise(vWorld.xy * 6.0 + vWorld.zy * 5.0);
        s = Surface(toLinear(vec3(0.9, 0.88, 0.83) * (0.92 + 0.08 * n)), 0.25, 40.0, vec3(0), 0.35);
    } else if (m == 46) {          // red damask
        vec2 q = vec2(vWorld.x + vWorld.z, vWorld.y) * 2.5;
        float pat = 0.5 + 0.5 * sin(q.x * 3.0) * sin(q.y * 3.0);
        s = Surface(toLinear(vec3(0.42, 0.08, 0.09) * (0.85 + 0.2 * pat)), 0.05, 10.0, vec3(0), 0.2);
    } else if (m == 47) {          // skylight
        s = Surface(vec3(0.0), 0.0, 1.0, toLinear(vec3(1.0, 0.97, 0.9)) * (0.5 + 1.6 * (1.0 - uNight)), 0.0);
    } else if (m == 48) {          // gilded frame
        float n = noise(vWorld.xy * 30.0 + vWorld.zy * 30.0);
        s = Surface(toLinear(vec3(0.75, 0.56, 0.22) * (0.8 + 0.3 * n)), 0.9, 50.0, vec3(0), 0.0);
    } else if (m == 49) {          // the green SORTIE sign
        s = Surface(toLinear(vec3(0.1, 0.7, 0.3)), 0.0, 8.0, toLinear(vec3(0.15, 1.0, 0.45)) * 2.0, 0.0);
    } else if (m == 51) {          // a canvas from its seed
        s = Surface(toLinear(seeded(clamp(vUV, 0.0, 1.0), vSeed)), 0.1, 24.0, vec3(0), 0.0);
    } else if (m == 92) {          // a drawing on paper, framed
        s = Surface(toLinear(drawing(clamp(vUV, 0.0, 1.0), vSeed)), 0.05, 12.0, vec3(0), 0.0);
    } else if (m == 52) {          // polished concrete
        float n = noise(vWorld.xz * 1.7) * 0.6 + noise(vWorld.xz * 9.0) * 0.4;
        s = Surface(toLinear(vec3(0.58, 0.58, 0.56) * (0.9 + 0.12 * n)), 0.5, 60.0, vec3(0), 0.0);
    } else if (m == 53) {          // a white gallery wall
        s = Surface(toLinear(vec3(0.94, 0.94, 0.93)), 0.0, 8.0, vec3(0), 0.0);
    } else if (m == 54) {          // painted steel indoors, in uCarColor (sculptures, pipes)
        s = Surface(toLinear(uCarColor), 0.6, 70.0, vec3(0), 0.0);
    } else if (m == 55) {          // a poster, from its seed
        vec4 p = poster(clamp(vUV, 0.0, 1.0), vSeed);
        gAlpha = p.a;
        s = Surface(toLinear(p.rgb), 0.05, 12.0, vec3(0), 0.0);
    } else if (m == 56) {          // Paris green cast iron
        s = Surface(toLinear(vec3(0.10, 0.21, 0.15)), 0.35, 30.0, vec3(0), 0.0);
    } else if (m == 57) {          // a tag sprayed on a wall
        vec4 g = graffiti(clamp(vUV, 0.0, 1.0), vSeed);
        gAlpha = g.a;
        s = Surface(toLinear(g.rgb), 0.2, 20.0, vec3(0), 0.0);
    } else if (m == 58) {          // newspaper
        s = Surface(toLinear(newspaper(fract(vUV))), 0.0, 8.0, vec3(0), 0.3);
    } else if (m == 59) {          // a decal; how faint in uExtraColor.x
        float spray = 0.55 + 0.45 * noise(vWorld.xz * 23.0) * noise(vWorld.xz * 7.0 + 3.0);
        gAlpha = uExtraColor.x * spray;
        s = Surface(toLinear(vec3(0.10, 0.32, 1.0)), 0.0, 8.0, toLinear(vec3(0.02, 0.06, 0.2)), 0.0);
    } else if (m == 60) {          // the planks of a wooden chalet
        float board = fract(vWorld.y * 5.0);
        float n = noise(vec2(vWorld.x + vWorld.z, vWorld.y * 5.0) * vec2(3.0, 1.0));
        vec3 wood = vec3(0.50, 0.32, 0.17) * (0.8 + 0.3 * n) * (0.75 + 0.25 * smoothstep(0.0, 0.08, board));
        s = Surface(toLinear(wood), 0.05, 10.0, vec3(0), 0.1);
    } else if (m == 61) {          // the warm light inside a stall
        s = Surface(toLinear(vec3(0.95, 0.75, 0.45)), 0.0, 8.0,
                    toLinear(vec3(1.0, 0.72, 0.38)) * (0.35 + 1.6 * uNight), 0.0);
    } else if (m == 62) {          // ice
        float scratch = noise(vWorld.xz * vec2(30.0, 3.0)) * noise(vWorld.zx * vec2(25.0, 4.0));
        s = Surface(toLinear(vec3(0.82, 0.9, 0.97) * (0.9 + 0.15 * scratch)), 0.9, 140.0, vec3(0), 0.0);
    } else if (m == 63 || m == 93) {
        // moving light, by pattern (seed) and time; 93: a video on a
        // screen, opaque, lit, with fine lines
        vec4 l = lightShow(clamp(vUV, 0.0, 1.0), vSeed, uTime);
        if (m == 93) {
            vec3 v = l.rgb * (0.85 + 0.15 * step(0.5, fract(vUV.y * 240.0)));
            s = Surface(vec3(0.02), 0.3, 40.0, toLinear(v) * 1.8 + vec3(0.004), 0.0);
        } else {
            gAlpha = l.a;
            s = Surface(vec3(0.0), 0.0, 8.0, toLinear(l.rgb) * (0.8 + 4.5 * uNight), 0.0);
        }
    } else if (m == 65) {          // a striped awning
        vec3 c1 = posterColour(floor(vSeed));
        float st = step(0.5, fract(vUV.x * 6.0));
        s = Surface(toLinear(mix(c1, vec3(0.95, 0.94, 0.9), st)), 0.05, 10.0, vec3(0), 0.3);
    } else if (m == 66) {          // books standing in a row
        float col = floor(vUV.x * 40.0);
        float hgt = 0.65 + 0.35 * hash(vec2(col, vSeed));
        vec3 c = posterColour(floor(hash(vec2(col, vSeed + 1.0)) * 8.0)) * (0.55 + 0.35 * hash(vec2(col, 3.0)));
        float gap = step(0.08, fract(vUV.x * 40.0));
        s = Surface(toLinear(mix(vec3(0.12, 0.1, 0.08), c, gap * step(vUV.y, hgt))), 0.05, 10.0, vec3(0), 0.0);
    } else if (m == 67) {          // a round cast-iron cover in the road
        vec2 q = vUV * 2.0 - 1.0;
        float r = length(q);
        gAlpha = 1.0 - smoothstep(0.96, 1.0, r);
        float ring = smoothstep(0.86, 0.9, r) * (1.0 - smoothstep(0.94, 0.97, r));
        float grid = step(0.7, fract(q.x * 6.0)) + step(0.7, fract(q.y * 6.0));
        float letters = step(0.72, r) * step(r, 0.84) * step(0.5, fract(atan(q.y, q.x) * 6.0));
        vec3 c = vec3(0.13, 0.13, 0.14) * (0.8 + 0.3 * clamp(grid * step(r, 0.68), 0.0, 1.0) + 0.4 * ring + 0.25 * letters);
        s = Surface(toLinear(c * (0.85 + 0.2 * noise(vWorld.xz * 9.0))), 0.35, 30.0, vec3(0), 0.0);
    } else if (m == 68) {          // a grate: bars over the dark
        float bar = step(0.55, fract(vUV.x * 9.0));
        vec3 c = mix(vec3(0.015), vec3(0.16, 0.16, 0.17), bar);
        s = Surface(toLinear(c), 0.3, 30.0, vec3(0), 0.0);
    } else if (m == 69) {          // water running along the gutter
        vec2 fd = vec2(cos(vSeed), sin(vSeed));
        float along = dot(vWorld.xz, fd), across = dot(vWorld.xz, vec2(-fd.y, fd.x));
        float flow = noise(vec2(along * 3.0 - uTime * 1.6, across * 12.0))
                   * noise(vec2(along * 7.0 - uTime * 2.3, across * 25.0 + 2.0));
        float edge = smoothstep(0.0, 0.25, vUV.y) * smoothstep(1.0, 0.6, vUV.y);
        gAlpha = 0.45 * edge + 0.35 * flow * edge;
        s = Surface(toLinear(vec3(0.32, 0.37, 0.42) + 0.25 * flow), 1.0, 160.0, vec3(0), 0.0);
    } else if (m == 70) {          // the dark mouth of an opening
        s = Surface(vec3(0.004), 0.0, 8.0, vec3(0), 0.0);
    } else if (m == 71) {          // shiny red rubber
        s = Surface(toLinear(vec3(0.85, 0.04, 0.05)), 0.9, 90.0, toLinear(vec3(0.05, 0.0, 0.0)), 0.2);
    } else if (m == 72) {          // two small lights in the dark, now and then
        float on = step(0.08, fract(uTime * 0.21 + vSeed)) * step(0.5, fract(uTime * 0.05 + vSeed * 0.37));
        s = Surface(vec3(0.0), 0.0, 8.0, toLinear(vec3(1.0, 0.92, 0.55)) * 1.6 * on, 0.0);
    } else if (m == 73) {          // a painted wall, from its seed, a little weathered
        vec3 c = seeded(clamp(vUV, 0.0, 1.0), vSeed);
        c *= 0.88 + 0.14 * noise(vWorld.xy * 3.0 + vWorld.zy * 2.0);
        s = Surface(toLinear(c), 0.05, 10.0, vec3(0), 0.0);
    } else if (m == 74) {          // a station sign: cream letters on dark green, a frame
        vec2 uv = clamp(vUV, 0.0, 1.0);
        float frame = step(uv.x, 0.03) + step(0.97, uv.x) + step(uv.y, 0.1) + step(0.9, uv.y);
        float x = uv.x * 13.0;
        float letter = step(0.28, uv.y) * step(uv.y, 0.72) * step(0.08, uv.x) * step(uv.x, 0.92)
                     * step(0.18, fract(x)) * step(fract(x), 0.82)
                     * (0.6 + 0.4 * step(0.5, fract(x * 2.0 + uv.y * 3.0)));
        vec3 c = mix(vec3(0.08, 0.2, 0.14), vec3(0.95, 0.88, 0.68), clamp(letter + frame * 0.6, 0.0, 1.0));
        s = Surface(toLinear(c), 0.15, 20.0, toLinear(c) * 0.25 * uNight, 0.0);
    } else if (m == 75) {          // the M of the metro on a yellow disc
        vec2 q = clamp(vUV, 0.0, 1.0) * 2.0 - 1.0;
        float disc = step(length(q), 0.95);
        gAlpha = disc;
        float m1 = step(abs(q.x), 0.55) * step(abs(q.y), 0.55);
        float stems = step(0.38, abs(q.x)) + step(abs(abs(q.x) - (0.55 - (q.y + 0.55) * 0.25)), 0.12) * step(0.0, q.y);
        float mm = m1 * clamp(stems, 0.0, 1.0);
        vec3 c = mix(vec3(0.98, 0.78, 0.1), vec3(0.08, 0.08, 0.08), mm);
        s = Surface(toLinear(c), 0.3, 30.0, toLinear(c) * 0.4 * uNight, 0.0);
    } else if (m == 76) {          // amber lamp glass, lit at night
        s = Surface(toLinear(vec3(0.95, 0.45, 0.12)), 0.6, 60.0,
                    toLinear(vec3(1.0, 0.55, 0.15)) * (0.15 + 2.5 * uNight), 0.0);
    } else if (m == 77) {          // a wall of stacked bones: rows of ends, now and then a skull
        vec2 g = vec2((vWorld.x + vWorld.z) * 6.0, vWorld.y * 9.0);
        vec2 id = floor(g), f = fract(g) - 0.5;
        float knob = smoothstep(0.42, 0.2, length(f * vec2(1.0, 1.4)));
        vec2 sg = vec2((vWorld.x + vWorld.z) * 1.4, vWorld.y * 2.2);
        vec2 sid = floor(sg), sf = fract(sg) - 0.5;
        float row = step(0.5, fract(sid.y * 0.5));
        float skull = row * step(0.55, hash(sid)) * smoothstep(0.38, 0.3, length(sf * vec2(1.0, 1.2)));
        float eyes = skull * smoothstep(0.1, 0.06, min(length(sf - vec2(-0.12, 0.05)), length(sf - vec2(0.12, 0.05))));
        vec3 c = vec3(0.62, 0.55, 0.42) * (0.55 + 0.45 * knob) * (0.85 + 0.2 * hash(id));
        c = mix(c, vec3(0.72, 0.66, 0.52), skull);
        c = mix(c, vec3(0.05, 0.04, 0.03), eyes);
        s = Surface(toLinear(c), 0.05, 10.0, vec3(0), 0.0);
    } else if (m == 78) {          // polished brass
        s = Surface(toLinear(vec3(0.85, 0.65, 0.25)), 0.9, 80.0, vec3(0), 0.0);
    } else if (m == 79) {          // a candle flame / a torch
        float flicker = 0.75 + 0.15 * sin(uTime * 13.0 + vWorld.x * 7.0) + 0.1 * sin(uTime * 23.0 + vWorld.z * 5.0);
        s = Surface(vec3(1.0, 0.8, 0.4), 0.0, 8.0, vec3(1.6, 1.0, 0.45) * flicker, 0.0);
    } else if (m == 81) {          // cardboard cartons, with a band of tape
        float tape = smoothstep(0.03, 0.0, abs(fract(vWorld.x * 2.1 + vWorld.z * 2.1) - 0.5) - 0.06);
        s = Surface(toLinear(mix(vec3(0.66, 0.5, 0.32), vec3(0.78, 0.66, 0.46), tape)), 0.05, 6.0, vec3(0), 0.0);
    } else if (m == 82) {          // a firm's blue band on a van
        s = Surface(toLinear(vec3(0.08, 0.2, 0.55)), 0.5, 40.0, vec3(0), 0.0);
    } else if (m == 83) {          // copper gone green (verdigris), darker in the folds
        float n = fbm(vWorld.xz * 3.0 + vWorld.y * 2.0);
        vec3 c = mix(vec3(0.30, 0.55, 0.47), vec3(0.42, 0.66, 0.56), n);
        c = mix(c * 0.7, c, smoothstep(-0.3, 0.6, N.y + 0.3));
        s = Surface(toLinear(c), 0.25, 24.0, vec3(0), 0.0);
    } else if (m == 84) {          // dug earth, lumpy
        float n = fbm(vWorld.xz * 2.5 + vWorld.y);
        s = Surface(toLinear(mix(vec3(0.30, 0.22, 0.14), vec3(0.46, 0.35, 0.24), n)), 0.02, 4.0, vec3(0), 0.0);
    } else if (m == 85) {          // a traffic cone: orange, a white band
        float band = step(0.5, fract(vWorld.y * 3.3)) * step(fract(vWorld.y * 3.3), 0.75);
        s = Surface(toLinear(mix(vec3(0.95, 0.38, 0.05), vec3(0.95), band)), 0.3, 20.0,
                    vec3(0.25, 0.08, 0.0) * uNight, 0.0);
    } else if (m == 86) {          // signal red paint (barriers, signs)
        s = Surface(toLinear(vec3(0.75, 0.06, 0.05)), 0.3, 24.0, vec3(0), 0.0);
    } else if (m == 88) {          // the metro's white bevelled tiles, in rows
        vec2 q = vec2(vWorld.x + (abs(N.x) > 0.5 ? vWorld.z : 0.0), vWorld.y + (abs(N.y) > 0.5 ? vWorld.z : 0.0));
        vec2 g = vec2(q.x / 0.3, q.y / 0.15);
        g.x += 0.5 * mod(floor(g.y), 2.0);
        vec2 fw = fwidth(g);
        vec2 f = fract(g);
        float e = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
        float detail = 1.0 - smoothstep(0.15, 0.45, max(fw.x, fw.y));   // fade out far off, no flicker
        float grout = (1.0 - smoothstep(0.0, 0.05 + fw.x, e)) * detail;
        float bevel = mix(1.0, smoothstep(0.0, 0.25, e), detail);
        vec3 c = mix(vec3(0.93, 0.92, 0.88) * (0.85 + 0.15 * bevel), vec3(0.62, 0.6, 0.55), grout);
        s = Surface(toLinear(c), 0.6, 70.0, vec3(0), 0.0);
    } else if (m == 90) {          // a statue's weathered stone, darker and greener low down
        float n = fbm(vWorld.xz * 2.0 + vWorld.y * 1.5);
        vec3 c = mix(vec3(0.52, 0.5, 0.45), vec3(0.66, 0.63, 0.56), n);
        c = mix(c * vec3(0.7, 0.75, 0.68), c, smoothstep(uMistY + 1.0, uMistY + 4.0, vWorld.y));
        s = Surface(toLinear(c), 0.05, 10.0, vec3(0), 0.0);
    } else if (m == 89) {          // a baguette's crust: golden, the cuts paler
        float cut = smoothstep(0.35, 0.5, abs(fract(vWorld.y * 9.0 + vWorld.x * 3.0) - 0.5));
        s = Surface(toLinear(mix(vec3(0.78, 0.52, 0.22), vec3(0.93, 0.8, 0.55), cut)), 0.15, 12.0, vec3(0), 0.0);
    } else if (m == 87) {          // a Vélib' bike's mint-green frame
        s = Surface(toLinear(vec3(0.45, 0.78, 0.62)), 0.45, 36.0, vec3(0), 0.0);
    } else if (m == 80) {          // a delivery van's white paint
        s = Surface(toLinear(vec3(0.9, 0.9, 0.88)), 0.5, 40.0, vec3(0), 0.0);
    } else if (m == 50) {          // a lamp in uExtraColor: the taxi sign, a police light bar
        s = Surface(toLinear(uExtraColor), 0.3, 16.0, toLinear(uExtraColor) * (1.2 + 3.0 * uNight), 0.0);
    } else if (m == 38) {          // the star on top
        s = Surface(toLinear(vec3(1.0, 0.85, 0.35)), 0.8, 40.0,
                    toLinear(vec3(1.0, 0.85, 0.4)) * (0.6 + 4.0 * uNight), 0.0);
    } else if (m == 15) {
        s = Surface(toLinear(uCarColor), 0.8, 90.0, vec3(0), 0.0);
    } else if (m == 16) {
        s = Surface(toLinear(pow(glass(N, V, 0.0), vec3(1.0 / 2.2))), 1.0, 120.0, vec3(0), 0.0);
    } else if (m == 17) {
        s = Surface(toLinear(vec3(0.04)), 0.0, 8.0, vec3(0), 0.0);
    } else if (m == 18) {
        s = Surface(vec3(0.9), 0.0, 8.0, vec3(1.2, 1.15, 1.0) * (1.0 + 3.0 * uNight), 0.0);
    } else if (m == 19) {
        s = Surface(toLinear(vec3(0.5, 0.02, 0.02)), 0.3, 32.0, vec3(0.6, 0.0, 0.0) * (1.0 + 2.0 * uNight), 0.0);
    } else if (m == 22) {
        s = quay(vUV, vSeed);
    } else if (m == 23) {          // chimney stack: plaster or brick, sooty top
        bool brick = vSeed > 0.8;
        vec3 c = brick ? vec3(0.56, 0.31, 0.23) : mix(vec3(0.74, 0.66, 0.56), vec3(0.82, 0.78, 0.70), vSeed);
        c *= 0.85 + 0.2 * noise(vWorld.xz * 3.0 + vWorld.y);
        if (brick) c *= 1.0 - 0.25 * fpulse(0.0, 0.12, vWorld.y * 13.0, fwidth(vWorld.y) * 13.0);
        s = Surface(toLinear(c), 0.0, 8.0, vec3(0), 0.0);
    } else if (m == 24) {          // terracotta chimney pots in a row
        float pot = fpulse(0.1, 0.75, vUV.x / 0.42, fwidth(vUV.x) / 0.42);
        vec3 c = mix(vec3(0.12, 0.10, 0.09), vec3(0.66, 0.36, 0.22) * (0.85 + 0.3 * hash(vec2(floor(vUV.x / 0.42), vSeed))), pot);
        if (N.y > 0.5) c = vec3(0.10, 0.08, 0.07);
        s = Surface(toLinear(c), 0.0, 8.0, vec3(0), 0.0);
    } else if (m == 25) {          // lead / slate dome with ribs
        float rib = fpulse(0.0, 0.08, vUV.x, fwidth(vUV.x));
        vec3 c = roofColour(vec3(0.42, 0.46, 0.50)) * (0.85 + 0.2 * noise(vWorld.xy * 0.5)) * (1.0 - 0.25 * rib);
        s = Surface(toLinear(c), 0.35, 40.0, vec3(0), 0.0);
    } else if (m == 26) {          // painted cast-iron lamp post
        s = Surface(toLinear(vec3(0.06, 0.08, 0.07)), 0.4, 40.0, vec3(0), 0.0);
    } else if (m == 28) {          // traffic light lamp
        float on = signalOn(vSeed, vUV.x, vUV.y);
        vec3 col = vSeed < 0.5 ? vec3(1.0, 0.08, 0.04)
                 : vSeed < 1.5 ? vec3(1.0, 0.55, 0.05) : vec3(0.1, 1.0, 0.45);
        s = Surface(toLinear(col * 0.12), 0.5, 60.0, col * on * (1.5 + 2.5 * uNight), 0.0);
    } else if (m == 29) {          // dressed stone of monuments: courses and joints
        vec2 fw = fwidth(vUV);
        float row = floor(vUV.y / 0.6);
        float u = vUV.x / 1.4 + 0.5 * mod(row, 2.0);
        float joint = max(fpulse(0.0, 0.03, u, fw.x / 1.4), fpulse(0.0, 0.04, vUV.y / 0.6, fw.y / 0.6));
        float detail = 1.0 - smoothstep(0.3, 0.7, max(fw.x, fw.y));
        vec3 c = vec3(0.86, 0.82, 0.73) * (0.92 + 0.1 * hash(vec2(floor(u), row)));
        c = mix(c, c * 0.8, joint * detail);
        c *= 0.85 + 0.15 * smoothstep(0.0, 8.0, vWorld.y);
        s = Surface(toLinear(c), 0.05, 16.0, vec3(0), 0.0);
        if (uNight > 0.01)   // floodlit monuments
            s.emissive = toLinear(vec3(1.0, 0.86, 0.62)) * 0.35 * uNight;
    } else if (m == 33) {          // wrought-iron lattice, golden lights at night
        vec2 p = vUV / 3.0;
        vec2 fw = max(fwidth(p), vec2(1e-4));
        float d1 = fpulse(0.0, 0.14, p.x + p.y, fw.x + fw.y);
        float d2 = fpulse(0.0, 0.14, p.x - p.y, fw.x + fw.y);
        float hb = fpulse(0.0, 0.18, p.y, fw.y);
        float edge = 1.0 - smoothstep(0.3, 1.2, min(vUV.x, 1e3));   // solid corner posts
        float bars = clamp(max(max(d1, d2), max(hb, edge)), 0.0, 1.0);
        // far away the lattice reads as a dense, darker surface
        bars = mix(bars, 0.75, smoothstep(0.2, 0.6, max(fw.x, fw.y)));
        gAlpha = bars;
        vec3 iron = vec3(0.44, 0.39, 0.31) * (0.85 + 0.2 * noise(vWorld.xy * 0.3));
        s = Surface(toLinear(iron), 0.25, 30.0, toLinear(vec3(1.0, 0.72, 0.32)) * 1.6 * uTowerLights, 0.0);
        // the sparkle: thousands of flash bulbs going off at random.  The
        // cells grow with distance (in steps) so a flash stays a dot.
        if (uSparkle > 0.0) {
            float dist = length(vWorld - uCamPos);
            float cell = exp2(ceil(log2(max(0.6, dist * 0.004))));
            vec3 q = floor(vWorld / cell);
            float t = floor(uTime * 9.0 + hash(q.xz + q.y) * 7.0);
            float r = hash(vec2(dot(q, vec3(1.0, 57.0, 113.0)) * 0.013, t * 0.071));
            vec3 f = fract(vWorld / cell) - 0.5;
            if (r > 0.9 && length(f) < 0.3) {
                s.emissive += vec3(6.0, 6.2, 7.0) * uSparkle;
                gAlpha = 1.0;
            }
        }
    } else if (m == 34) {          // wrought-iron balcony railing (see-through)
        vec2 fw = max(fwidth(vUV), vec2(1e-4));
        float y = vUV.y - floor(vUV.y);                   // 0 .. 1 over the railing
        float bars = fpulse(0.0, 0.18, vUV.x / 0.11, fw.x / 0.11);
        float rails = fpulse(0.0, 0.07, y, fw.y) + fpulse(0.93, 1.0, y, fw.y)
                    + fpulse(0.45, 0.5, y, fw.y);
        // a band of scrolls between the lower rails
        float scroll = step(0.08, y) * step(y, 0.44)
                     * fpulse(0.42, 0.58, length(fract(vec2(vUV.x / 0.36, y / 0.36)) - 0.5) * 2.0, 0.05);
        gAlpha = clamp(bars + rails + scroll, 0.0, 1.0);
        gAlpha = mix(gAlpha, 0.55, smoothstep(0.3, 0.8, max(fw.x, fw.y) * 8.0));
        s = Surface(toLinear(vec3(0.06, 0.06, 0.065)), 0.3, 40.0, vec3(0), 0.0);
    } else if (m == 35) {          // herringbone parquet (point de Hongrie)
        vec2 p = vUV;
        vec2 q = vec2(p.x + p.y, p.x - p.y) * 0.7071;     // 45 degrees
        float col = floor(q.x / 0.42);
        float flip = mod(col, 2.0);
        float along = (flip > 0.5 ? q.y : -q.y) + q.x;    // zig-zag offset
        float plank = floor(along / 0.09);
        float joint = max(fpulse(0.0, 0.04, q.x / 0.42, fwidth(q.x) / 0.42),
                          fpulse(0.0, 0.08, along / 0.09, fwidth(along) / 0.09));
        vec3 oak = mix(vec3(0.50, 0.33, 0.18), vec3(0.62, 0.43, 0.25), hash(vec2(col, plank)));
        oak *= 0.9 + 0.15 * noise(vec2(along * 8.0, q.x * 40.0));
        s = Surface(toLinear(mix(oak, oak * 0.55, joint * 0.7)), 0.35, 60.0, vec3(0), 0.0);
    } else if (m == 36) {          // painted plaster
        vec3 c = vec3(0.90, 0.87, 0.80) * (0.96 + 0.05 * noise(vWorld.xz * 2.0 + vWorld.y));
        s = Surface(toLinear(c), 0.02, 8.0, vec3(0), 0.0);
    } else if (m == 30) {          // clothes
        s = Surface(toLinear(uCarColor), 0.0, 8.0, vec3(0), 0.2);
    } else if (m == 31) {          // skin
        s = Surface(toLinear(uExtraColor), 0.1, 12.0, vec3(0), 0.3);
    } else if (m == 32) {          // trousers
        s = Surface(toLinear(uExtraColor2), 0.0, 8.0, vec3(0), 0.1);
    } else if (m == 27) {          // lantern glass
        vec3 glow = toLinear(vec3(1.0, 0.78, 0.48));
        s = Surface(toLinear(vec3(0.45, 0.45, 0.42)), 0.6, 60.0, glow * (0.05 + 4.0 * uNight), 0.0);
    } else {
        s = ground(m, vWorld.xz, vSeed);
        // fallen leaves on the pavements, squares and lawns
        if (uTrash > 0.0 && (m == 0 || m == 3 || m == 8)) {
            // the morning after: flyers, cups, cans and bottles on the pavements
            vec2 cell = floor(vWorld.xz / 0.5);
            float h = hash(cell + 7.7);
            vec2 f = fract(vWorld.xz / 0.5) - 0.5;
            float patch = noise(vWorld.xz * 0.12);
            if (h < uTrash * (0.08 + 0.3 * patch)) {
                float k = fract(h * 53.0);
                float a = h * 40.0;
                vec2 r = vec2(cos(a) * f.x - sin(a) * f.y, sin(a) * f.x + cos(a) * f.y);
                bool paper = k < 0.6 && abs(r.x) < 0.2 && abs(r.y) < 0.14;
                bool can = k >= 0.6 && abs(r.x) < 0.18 && abs(r.y) < 0.05;
                if (paper) {
                    vec3 pc = k < 0.25 ? vec3(0.92, 0.91, 0.88) : k < 0.45 ? vec3(0.95, 0.85, 0.3) : vec3(0.85, 0.3, 0.3);
                    s.albedo = toLinear(pc);
                } else if (can) {
                    vec3 cc = k < 0.75 ? vec3(0.75, 0.1, 0.1) : k < 0.88 ? vec3(0.2, 0.45, 0.2) : vec3(0.7, 0.72, 0.75);
                    s.albedo = toLinear(cc);
                    s.spec = 0.8;
                    s.gloss = 60.0;
                }
            }
        }
        if (uPetals > 0.0 && (m == 0 || m == 3 || m == 4 || m == 8)) {
            vec2 cell = floor(vWorld.xz / 0.09);
            float h = hash(cell + 7.7);
            vec2 f = fract(vWorld.xz / 0.09) - 0.5;
            float patch = smoothstep(0.45, 0.8, noise(vWorld.xz * 0.06 + 2.0));
            if (h < uPetals * 0.5 * patch && dot(f, f) < 0.09) {
                s.albedo = toLinear(fract(h * 53.0) < 0.5 ? vec3(0.97, 0.78, 0.85) : vec3(0.97, 0.96, 0.92));
            }
        }
        if (uLitter > 0.0 && (m == 0 || m == 3 || m == 4 || m == 8)) {
            vec2 cell = floor(vWorld.xz / 0.22);
            float h = hash(cell + 3.1);
            vec2 f = fract(vWorld.xz / 0.22) - 0.5;
            float patch = noise(vWorld.xz * 0.25);
            if (h < uLitter * (0.25 + 0.6 * patch) && dot(f * vec2(1.0, 1.6), f * vec2(1.0, 1.6)) < 0.16) {
                float k = fract(h * 37.0);
                vec3 lc = k < 0.4 ? vec3(0.70, 0.48, 0.10) : k < 0.75 ? vec3(0.60, 0.28, 0.07)
                        : vec3(0.42, 0.27, 0.12);
                s.albedo = toLinear(lc);
            }
        }
    }

    // Rain: horizontal ground and roofs darken and turn glossy, with
    // puddles that mirror the sky and the street lamps
    float wetGloss = 0.0;
    float puddle = 0.0;
    if (uWet > 0.01 && (m <= 9 || m == 12 || m == 20 || m == 21 || m == 22 || m == 11)) {
        float flat_ = smoothstep(0.7, 0.95, N.y);
        float porous = (m == 4 || m == 7 || m == 20) ? 0.3 : 1.0;   // grass soaks it up
        float w = uWet * porous;
        s.albedo *= 1.0 - 0.45 * w;
        puddle = flat_ * w * smoothstep(0.55, 0.72, fbm(vWorld.xz * 0.12 + 3.0))
               * (m == 1 || m == 0 || m == 8 || m == 9 ? 1.0 : 0.0);
        wetGloss = w > 0.05 ? mix(60.0, 220.0, puddle) : 0.0;
        s.spec = max(s.spec, 0.6 * w * flat_ + 0.4 * puddle);
        s.gloss = max(s.gloss, mix(40.0, 200.0, puddle));
    }
    if (uWet > 0.01 && (m == 10 || m == 11)) {
        s.albedo *= 1.0 - 0.25 * uWet;   // rain-darkened stone and zinc
    }

    // Snow settles on everything that faces up; the traffic keeps the
    // roads to a grey slush
    if (uSnowCover > 0.01 && m != 6 && !(m >= 15 && m <= 19) && !(m >= 26 && m <= 28)
        && !(m >= 30 && m <= 36) && m < 40) {
        float up = smoothstep(0.35, 0.8, N.y);
        bool road = (m == 1 || m == 21 || m == 9);
        float amount = uSnowCover * (road ? 0.45 : 1.0);
        float patch = fbm(vWorld.xz * 0.35 + 11.0);
        float cover = up * smoothstep(0.0, 0.25, amount * 1.3 - 0.5 * patch + 0.1);
        vec3 snow = road ? toLinear(vec3(0.55, 0.56, 0.58)) : toLinear(vec3(0.93, 0.95, 0.99));
        s.albedo = mix(s.albedo, snow, cover);
        s.spec = mix(s.spec, 0.15, cover);
        s.gloss = mix(s.gloss, 20.0, cover);
        s.wrap = mix(s.wrap, 0.2, cover);
    }

    float shadow = shadowFactor(N, L);
    float ndl = dot(N, L);
    float diffuse = s.wrap > 0.0 ? clamp((ndl + s.wrap) / (1.0 + s.wrap), 0.0, 1.0)
                                 : max(ndl, 0.0);
    vec3 ambient = mix(uAmbGround, uAmbSky, N.y * 0.5 + 0.5);
    // Inside the apartment: daylight bouncing in through the windows
    if (m == 35 || m == 36 || (m >= 44 && m <= 48) || (m >= 51 && m <= 54)) {
        float day = dot(uSunColor, vec3(0.3, 0.5, 0.2));
        ambient = vec3(1.0, 0.93, 0.84) * (0.05 + 0.22 * day) + 0.3 * uAmbSky;
    }
    // In the Louvre: even, warm gallery light, day and night
    if (uGallery > 2.5) {          // underground: only the light you carry
        float d = length(vWorld - uCamPos);
        ambient = vec3(1.0, 0.7, 0.4) * (1.6 / (1.0 + 0.6 * d * d)) + vec3(0.003);
    } else if (uGallery > 1.5) {   // hall B: cool, bright, white
        ambient = vec3(0.95, 0.97, 1.0) * 0.95;
    } else if (uGallery > 0.5) {
        ambient = vec3(1.0, 0.95, 0.86) * 0.8;
    }
    // Cheap ambient occlusion: darker near the ground for walls
    float ao = (m >= 10 && m <= 11) ? 0.65 + 0.35 * smoothstep(0.0, 6.0, vWorld.y) : 1.0;
    if (m == 14) ao = 0.55 + 0.45 * clamp(N.y * 0.5 + 0.6, 0.0, 1.0);

    vec3 H = normalize(L + V);
    float spec = s.spec * pow(max(dot(N, H), 0.0), s.gloss) * shadow * step(0.0, ndl);

    vec3 lampSpec;
    vec3 lamps = localLightSpec(N, V, wetGloss, lampSpec);
    vec3 col = s.albedo * (uSunColor * diffuse * shadow + ambient * ao + lamps)
             + uSunColor * spec + s.emissive + lampSpec;
    // Hall B is underground: no sun, no city shadows, but an even light
    // from the ceiling, the same by day and by night
    if (uGallery > 2.5) {          // (no floodlights down here: only flames and signs glow)
        bool glows = m == 79 || m == 49 || m == 50 || m == 76;
        col = s.albedo * ambient + (glows ? s.emissive : vec3(0.0));
    } else if (uGallery > 1.5) {
        vec3 Lg = normalize(vec3(0.15, 1.0, 0.1));
        vec3 Hg = normalize(Lg + V);
        float sg = s.spec * pow(max(dot(N, Hg), 0.0), s.gloss);
        col = s.albedo * (ambient * ao + vec3(0.35) * max(dot(N, Lg), 0.0)) + vec3(0.25) * sg + s.emissive;
    }
    if (puddle > 0.0) {
        vec3 R = reflect(-V, N);
        float fres = 0.04 + 0.96 * pow(1.0 - max(dot(N, V), 0.0), 5.0);
        col = mix(col, toLinear(skyColor(R)) * 0.8, puddle * (0.25 + 0.6 * fres));
    }

    // A hot afternoon: far down the road the tarmac turns to sky, a
    // trembling mirage just above the horizon of the street
    if (uHeat > 0.0 && (m == 1 || m == 9 || m == 21) && N.y > 0.9) {
        float dist = length(uCamPos - vWorld);
        float graze = 1.0 - smoothstep(0.02, 0.07, V.y);
        float far_ = smoothstep(25.0, 70.0, dist);
        float shimmer = 0.6 + 0.4 * noise(vec2(vWorld.x * 0.15 + uTime * 1.3, vWorld.z * 0.15 - uTime * 0.9)
                                          + vec2(sin(uTime * 7.0 + vWorld.x), 0.0) * 0.4);
        float mir = uHeat * graze * far_ * shimmer;
        col = mix(col, toLinear(skyColor(reflect(-V, vec3(0.0, 1.0, 0.0)))) * 0.95, 0.85 * mir);
    }

    col = mix(col, fogColour(), fogAt(vWorld));

    col = col / (1.0 + col) * 1.25;   // gentle tone mapping
    if (uEra > 0.5) col = kodachrome(col);
    fragColor = vec4(pow(col, vec3(1.0 / 2.2)), gAlpha);
}
