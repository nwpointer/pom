attribute vec4 tangent;

varying vec2 vUv;
varying vec3 vWorldPosition;
varying vec3 vWorldNormal;
varying vec4 vWorldTangent;

uniform sampler2D uVertexDisplacementMap;
uniform float uVertexDisplacementScale;
uniform float uDisplacementScale;

void main() {
    vUv = uv;

    float displacement = texture2D(uVertexDisplacementMap, uv).r;
    vec3 displacedPosition = position + normal * (displacement * uVertexDisplacementScale + uDisplacementScale/2.0);

    vWorldPosition = (modelMatrix * vec4(displacedPosition, 1.0)).xyz;

    // Pass world normal and tangent to fragment shader for per-fragment TBN calculation
    vWorldNormal = normalize(mat3(modelMatrix) * normal);
    vWorldTangent = vec4(normalize(mat3(modelMatrix) * tangent.xyz), tangent.w);

    gl_Position = projectionMatrix * modelViewMatrix * vec4(displacedPosition, 1.0);
} 