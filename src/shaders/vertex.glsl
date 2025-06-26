attribute vec4 tangent;

varying vec2 vUv;
varying vec3 vWorldPosition;
varying vec3 vWorldNormal;
varying vec4 vWorldTangent;
// New: Smooth interpolated TBN for displaced surface
varying vec3 vSmoothWorldNormal;
varying vec3 vSmoothWorldTangent;
varying vec3 vSmoothWorldBitangent;

uniform sampler2D uVertexDisplacementMap;
uniform float uVertexDisplacementScale;
uniform float uDisplacementScale;

// Calculate smooth TBN by sampling neighboring points and interpolating
mat3 calculateSmoothTBN(vec3 pos, vec3 norm, vec3 tang, float tangentW, vec2 texCoord) {
    // If no vertex displacement, return original TBN
    if (uVertexDisplacementScale < 0.001) {
        vec3 worldNormal = normalize(mat3(modelMatrix) * norm);
        vec3 worldTangent = normalize(mat3(modelMatrix) * tang);
        vec3 worldBitangent = cross(worldNormal, worldTangent) * tangentW;
        return mat3(worldTangent, worldBitangent, worldNormal);
    }
    
    // Sample displacement at current and neighboring points
    // Use smaller texel size for more accurate gradients
    float texelSize = 1.0 / 1024.0;
    
    float h = texture2D(uVertexDisplacementMap, texCoord).r;
    float hRight = texture2D(uVertexDisplacementMap, texCoord + vec2(texelSize, 0.0)).r;
    float hLeft = texture2D(uVertexDisplacementMap, texCoord - vec2(texelSize, 0.0)).r;
    float hUp = texture2D(uVertexDisplacementMap, texCoord + vec2(0.0, texelSize)).r;
    float hDown = texture2D(uVertexDisplacementMap, texCoord - vec2(0.0, texelSize)).r;
    
    // Calculate central difference gradients for better accuracy
    float dhdu = (hRight - hLeft) * 0.5 * uVertexDisplacementScale;
    float dhdv = (hUp - hDown) * 0.5 * uVertexDisplacementScale;
    
    // Get original tangent space vectors in object space
    vec3 T = normalize(tang);
    vec3 N = normalize(norm);
    vec3 B = normalize(cross(N, T)) * tangentW;
    
    // Create displaced surface by moving points along normal
    vec3 currentPos = pos + N * (h * uVertexDisplacementScale);
    vec3 rightPos = pos + T * texelSize + N * (hRight * uVertexDisplacementScale);
    vec3 upPos = pos + B * texelSize + N * (hUp * uVertexDisplacementScale);
    
    // Calculate tangent vectors from displaced positions
    vec3 displacedTangent = normalize(rightPos - currentPos);
    vec3 displacedBitangent = normalize(upPos - currentPos);
    
    // Calculate normal from cross product of displaced tangent vectors
    vec3 displacedNormal = normalize(cross(displacedTangent, displacedBitangent));
    
    // Ensure consistent orientation with original normal
    if (dot(displacedNormal, N) < 0.0) {
        displacedNormal = -displacedNormal;
    }
    
    // Re-orthogonalize the basis
    displacedTangent = normalize(displacedTangent - dot(displacedTangent, displacedNormal) * displacedNormal);
    displacedBitangent = cross(displacedNormal, displacedTangent) * tangentW;
    
    // Transform to world space
    vec3 worldT = normalize(mat3(modelMatrix) * displacedTangent);
    vec3 worldB = normalize(mat3(modelMatrix) * displacedBitangent);
    vec3 worldN = normalize(mat3(modelMatrix) * displacedNormal);
    
    return mat3(worldT, worldB, worldN);
}

void main() {
    vUv = uv;

    float displacement = texture2D(uVertexDisplacementMap, uv).r;
    vec3 displacedPosition = position + normal * (displacement * uVertexDisplacementScale + uDisplacementScale/2.0);

    vWorldPosition = (modelMatrix * vec4(displacedPosition, 1.0)).xyz;

    // Calculate original TBN (for fallback/comparison)
    vWorldNormal = normalize(mat3(modelMatrix) * normal);
    vWorldTangent = vec4(normalize(mat3(modelMatrix) * tangent.xyz), tangent.w);

    // Calculate smooth interpolated TBN that accounts for displacement
    mat3 smoothTBN = calculateSmoothTBN(position, normal, tangent.xyz, tangent.w, uv);
    vSmoothWorldNormal = smoothTBN[2];
    vSmoothWorldTangent = smoothTBN[0];
    vSmoothWorldBitangent = smoothTBN[1];

    gl_Position = projectionMatrix * modelViewMatrix * vec4(displacedPosition, 1.0);
} 