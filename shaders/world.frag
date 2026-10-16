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
uniform vec4 uLights[64];    // street lamps: xyz position, w intensity
uniform int uLightCount;
uniform vec3 uHeadPos;       // player's headlights
uniform vec3 uHeadDir;
uniform float uHeadOn;
uniform vec3 uExtraColor;    // pedestrians: skin
uniform vec3 uExtraColor2;   // pedestrians: trousers
uniform float uWet;          // 0 dry .. 1 soaked streets

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

vec3 skyColor(vec3 dir)
{
    float t = pow(clamp(dir.y, 0.0, 1.0), 0.5);
    return mix(uSkyHorizon, uSkyZenith, t);
}

// ------------------------------------------------------------ materials ---

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

    if (style > 0.5) {   // monument: tall narrow windows
        float win = fpulse(0.42, 0.58, uv.x * 0.5, fw.x * 0.5)
                  * fpulse(0.15, 0.85, uv.y / 3.0, fw.y / 3.0);
        s.albedo = mix(s.albedo, toLinear(vec3(0.10, 0.10, 0.12)), win * 0.9);
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

// ------------------------------------------------------------------ main ---

void main()
{
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
        float fog = 1.0 - exp(-length(uCamPos - vWorld) * uFogDensity);
        col = mix(col, toLinear(uSkyHorizon), fog);
        col = col / (1.0 + col) * 1.25;
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
        s = Surface(toLinear(leaf), 0.0, 8.0, vec3(0), 0.45);
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
        s = Surface(toLinear(iron), 0.25, 30.0, toLinear(vec3(1.0, 0.72, 0.32)) * 1.6 * uNight, 0.0);
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

    float shadow = shadowFactor(N, L);
    float ndl = dot(N, L);
    float diffuse = s.wrap > 0.0 ? clamp((ndl + s.wrap) / (1.0 + s.wrap), 0.0, 1.0)
                                 : max(ndl, 0.0);
    vec3 ambient = mix(uAmbGround, uAmbSky, N.y * 0.5 + 0.5);
    // Cheap ambient occlusion: darker near the ground for walls
    float ao = (m >= 10 && m <= 11) ? 0.65 + 0.35 * smoothstep(0.0, 6.0, vWorld.y) : 1.0;
    if (m == 14) ao = 0.55 + 0.45 * clamp(N.y * 0.5 + 0.6, 0.0, 1.0);

    vec3 H = normalize(L + V);
    float spec = s.spec * pow(max(dot(N, H), 0.0), s.gloss) * shadow * step(0.0, ndl);

    vec3 lampSpec;
    vec3 lamps = localLightSpec(N, V, wetGloss, lampSpec);
    vec3 col = s.albedo * (uSunColor * diffuse * shadow + ambient * ao + lamps)
             + uSunColor * spec + s.emissive + lampSpec;
    if (puddle > 0.0) {
        vec3 R = reflect(-V, N);
        float fres = 0.04 + 0.96 * pow(1.0 - max(dot(N, V), 0.0), 5.0);
        col = mix(col, toLinear(skyColor(R)) * 0.8, puddle * (0.25 + 0.6 * fres));
    }

    float fog = 1.0 - exp(-length(uCamPos - vWorld) * uFogDensity);
    col = mix(col, toLinear(uSkyHorizon), fog);

    col = col / (1.0 + col) * 1.25;   // gentle tone mapping
    fragColor = vec4(pow(col, vec3(1.0 / 2.2)), gAlpha);
}
