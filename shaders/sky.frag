#version 330 core

in vec2 vNdc;

uniform mat4 uInvViewProj;
uniform vec3 uCamPos;
uniform vec3 uSunDir;        // sun by day, moon by night
uniform vec3 uSkyZenith;
uniform vec3 uSkyHorizon;
uniform float uNight;
uniform float uClouds;      // 0 clear .. 1 overcast (hides stars and moon)

out vec4 fragColor;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }

void main()
{
    vec4 p = uInvViewProj * vec4(vNdc, 1.0, 1.0);
    vec3 dir = normalize(p.xyz / p.w - uCamPos);
    float t = pow(clamp(dir.y, 0.0, 1.0), 0.5);
    vec3 col = mix(uSkyHorizon, uSkyZenith, t);
    float sd = max(dot(dir, normalize(uSunDir)), 0.0);
    vec3 sunGlow = vec3(1.0, 0.9, 0.7) * (pow(sd, 1200.0) * 4.0 + pow(sd, 12.0) * 0.18);
    vec3 moon = vec3(0.85, 0.88, 0.95) * smoothstep(0.99985, 0.99992, sd)
              + vec3(0.10, 0.12, 0.18) * pow(sd, 40.0);
    col += mix(sunGlow, moon, uNight) * (1.0 - 0.9 * uClouds);

    // Stars, fading towards the (light-polluted) horizon
    if (uNight > 0.01 && dir.y > 0.0) {
        vec3 cell = floor(dir * 300.0);
        float h = hash(cell);
        float star = step(0.9965, h) * (0.4 + 0.6 * hash(cell + 7.0));
        col += vec3(star) * smoothstep(0.05, 0.4, dir.y) * uNight * (1.0 - uClouds);
    }
    fragColor = vec4(min(col, vec3(1.0)), 1.0);
}
