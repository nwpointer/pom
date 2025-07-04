attribute vec4 tangent;

varying vec2 vUv;
varying vec3 vWorldPosition;
varying mat3 vTBN;

uniform sampler2D uVertexDisplacementMap;
uniform sampler2D uDisplacementMap;
uniform float uVertexDisplacementScale;
uniform float uDisplacementScale;

void main() {
    vUv = uv;

    // Sample both displacement maps and combine them
    float vertexDisplacement = texture2D(uVertexDisplacementMap, uv).r * uVertexDisplacementScale;
    float detailDisplacement = texture2D(uDisplacementMap, uv).r * uDisplacementScale;
    float totalDisplacement = vertexDisplacement + detailDisplacement;
    
    vec3 displacedPosition = position + normal * totalDisplacement;

    vWorldPosition = (modelMatrix * vec4(displacedPosition, 1.0)).xyz;

    vec3 worldNormal = normalize(mat3(modelMatrix) * normal);
    vec3 worldTangent = normalize(mat3(modelMatrix) * tangent.xyz);
    vec3 worldBitangent = cross(worldNormal, worldTangent) * tangent.w;

    vTBN = mat3(worldTangent, worldBitangent, worldNormal);

    gl_Position = projectionMatrix * modelViewMatrix * vec4(displacedPosition, 1.0);
} 