// Dérive: open-world Paris in Ada
// Copyright (c) 2026 Ulrik Hørlyk Hjort
// SPDX-License-Identifier: MIT
//
#version 330 core

in vec2 vNdc;

uniform mat4 uInvViewProj;
uniform vec3 uCamPos;
uniform vec3 uSunDir;        // sun by day, moon by night
uniform vec3 uSkyZenith;
uniform vec3 uSkyHorizon;
uniform float uNight;
uniform float uClouds;      // 0 clear .. 1 overcast (hides stars and moon)
uniform vec3 uSunTrue;       // the sun, also below the horizon
uniform vec3 uMoonDir;
uniform float uMoonAge;      // 0 new, 0.5 full, 1 new again

out vec4 fragColor;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }

void main()
{
    vec4 p = uInvViewProj * vec4(vNdc, 1.0, 1.0);
    vec3 dir = normalize(p.xyz / p.w - uCamPos);
    float t = pow(clamp(dir.y, 0.0, 1.0), 0.5);
    vec3 col = mix(uSkyHorizon, uSkyZenith, t);
    float sd = max(dot(dir, normalize(uSunTrue)), 0.0);
    vec3 sunGlow = vec3(1.0, 0.9, 0.7) * (pow(sd, 1200.0) * 4.0 + pow(sd, 12.0) * 0.18);
    col += sunGlow * (1.0 - uNight) * (1.0 - 0.9 * uClouds);

    // The moon, with its phase: the side towards the sun is lit, the rest
    // shows a little earthshine
    vec3 md = normalize(uMoonDir);
    float ph = uMoonAge < 0.5 ? uMoonAge : 1.0 - uMoonAge;   // 0 new .. 0.5 full
    float elong = ph * 6.2831853;
    float illum = 0.5 - 0.5 * cos(elong);
    float onDisc = 0.0;
    const float R = 0.018;
    float msd = dot(dir, md);
    if (msd > 0.99 && dir.y > 0.0) {
        vec3 right = normalize(cross(md, abs(md.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0)));
        vec3 upv = cross(right, md);
        vec2 q = vec2(dot(dir, right), dot(dir, upv)) / R;
        float r2 = dot(q, q);
        if (r2 < 1.0) {
            vec3 n = vec3(q, sqrt(1.0 - r2));
            vec3 s = normalize(uSunTrue);
            vec2 s2 = vec2(dot(s, right), dot(s, upv));
            s2 = length(s2) > 1e-4 ? normalize(s2) : vec2(1.0, 0.0);
            vec3 L = vec3(s2 * sin(elong), -cos(elong));
            float lit = smoothstep(-0.04, 0.04, dot(n, L));
            float maria = 0.82 + 0.1 * sin(q.x * 5.0 + 1.3) * sin(q.y * 4.0 - 0.7)
                        + 0.08 * sin(q.x * 11.0 - q.y * 7.0);
            onDisc = smoothstep(1.0, 0.94, r2);
            vec3 mc = vec3(0.92, 0.93, 0.97) * (lit * maria + 0.03);
            float vis = mix(0.22, 1.0, uNight) * (1.0 - 0.9 * uClouds);
            col = mix(col, max(col, mc), onDisc * vis);
        }
    }
    col += vec3(0.10, 0.12, 0.18) * pow(max(msd, 0.0), 40.0) * illum * uNight
         * (1.0 - uClouds) * step(0.0, md.y);

    // Stars, fading towards the (light-polluted) horizon
    if (uNight > 0.01 && dir.y > 0.0) {
        vec3 cell = floor(dir * 300.0);
        float h = hash(cell);
        float star = step(0.9965, h) * (0.4 + 0.6 * hash(cell + 7.0));
        col += vec3(star) * smoothstep(0.05, 0.4, dir.y) * uNight * (1.0 - uClouds)
             * (1.0 - onDisc);
    }
    fragColor = vec4(min(col, vec3(1.0)), 1.0);
}
