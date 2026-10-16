#version 330 core

// One rain streak per two vertices.  aDrop.xyz are random numbers in
// [0, 1) placing the drop in a box that wraps around the camera, aDrop.w
// is 0 for the top of the streak and 1 for its bottom.
layout(location = 0) in vec4 aDrop;

uniform mat4 uViewProj;
uniform vec3 uCamPos;
uniform float uTime;
uniform float uAmount;

out float vAlpha;

const float BOX = 36.0;
const float HEIGHT = 28.0;
const float SPEED = 12.0;

void main()
{
    vec3 base;
    base.xz = uCamPos.xz + mod(aDrop.xz * BOX - uCamPos.xz, BOX) - 0.5 * BOX;
    base.y = uCamPos.y - 0.45 * HEIGHT + mod(aDrop.y * HEIGHT - uTime * SPEED, HEIGHT);
    vec3 p = base + vec3(0.12, -0.75, 0.05) * aDrop.w;
    float d = length(base - uCamPos);
    // fewer drops in light rain; fade with distance
    vAlpha = step(fract(aDrop.x * 57.31 + aDrop.z * 13.7), uAmount)
           * (1.0 - smoothstep(6.0, 17.0, d)) * (1.0 - 0.6 * aDrop.w);
    gl_Position = uViewProj * vec4(p, 1.0);
}
