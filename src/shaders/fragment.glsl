varying vec2 vUv;
varying vec3 vWorldPosition;
varying vec3 vWorldNormal;
varying vec4 vWorldTangent;
// New: Smooth interpolated TBN from vertex shader
varying vec3 vSmoothWorldNormal;
varying vec3 vSmoothWorldTangent;
varying vec3 vSmoothWorldBitangent;

uniform sampler2D uDiffuseMap;
uniform sampler2D uNormalMap;
uniform sampler2D uDisplacementMap;
uniform sampler2D uVertexDisplacementMap;
uniform float uDisplacementScale;
uniform float uVertexDisplacementScale;
uniform vec3 uCameraPosition;
uniform vec3 uLightDirection;
uniform float uShadowHardness;
uniform int uDebugMode; // 0=off, 1=tangent, 2=bitangent, 3=normal, 4=view_dir
uniform bool uUseSmoothTBN; // true=smooth interpolated, false=physically accurate
uniform bool uEnableShadows; // true=shadows enabled, false=no shadows

// Helper function to calculate TBN matrix per fragment
mat3 getTBNMatrix() {
    vec3 worldNormal = normalize(vWorldNormal);
    vec3 worldTangent = normalize(vWorldTangent.xyz);
    vec3 worldBitangent = cross(worldNormal, worldTangent) * vWorldTangent.w;
    return mat3(worldTangent, worldBitangent, worldNormal);
}

// Displacement-aware TBN matrix calculation
mat3 getDisplacedTBNMatrix(vec2 dx, vec2 dy) {
    // If no vertex displacement, use original TBN
    if (uVertexDisplacementScale < 0.001) {
        return getTBNMatrix();
    }
    
    // Calculate displaced surface normal using screen-space derivatives
    vec3 dpdx = dFdx(vWorldPosition);
    vec3 dpdy = dFdy(vWorldPosition);
    vec2 duvdx = dFdx(vUv);
    vec2 duvdy = dFdy(vUv);
    
    // Sample vertex displacement at neighboring points
    vec2 texelSize = vec2(1.0) / 1024.0; // Assume texture resolution
    float h = textureGrad(uVertexDisplacementMap, vUv, dx, dy).r * uVertexDisplacementScale;
    float dhdu = (textureGrad(uVertexDisplacementMap, vUv + vec2(texelSize.x, 0.0), dx, dy).r - 
                  textureGrad(uVertexDisplacementMap, vUv - vec2(texelSize.x, 0.0), dx, dy).r) * 0.5 * uVertexDisplacementScale;
    float dhdv = (textureGrad(uVertexDisplacementMap, vUv + vec2(0.0, texelSize.y), dx, dy).r - 
                  textureGrad(uVertexDisplacementMap, vUv - vec2(0.0, texelSize.y), dx, dy).r) * 0.5 * uVertexDisplacementScale;
    
    // Calculate Jacobian for UV to screen space mapping
    float jacobian = duvdx.x * duvdy.y - duvdx.y * duvdy.x;
    if (abs(jacobian) < 1e-8) {
        return getTBNMatrix(); // Fallback to original TBN
    }
    
    // Compute displaced tangent vectors
    float invJacobian = 1.0 / jacobian;
    vec2 invJ_row1 = vec2(duvdy.y, -duvdx.y) * invJacobian;
    vec2 invJ_row2 = vec2(-duvdy.x, duvdx.x) * invJacobian;
    
    // Transform position gradients to UV space
    vec3 dpdu = dpdx * invJ_row1.x + dpdy * invJ_row1.y;
    vec3 dpdv = dpdx * invJ_row2.x + dpdy * invJ_row2.y;
    
    // Add displacement gradients to surface tangents
    vec3 displacedTangent = dpdu + normalize(vWorldNormal) * dhdu;
    vec3 displacedBitangent = dpdv + normalize(vWorldNormal) * dhdv;
    
    // Compute displaced normal using cross product
    vec3 displacedNormal = normalize(cross(displacedTangent, displacedBitangent));
    
    // Ensure consistent handedness
    if (dot(displacedNormal, vWorldNormal) < 0.0) {
        displacedNormal = -displacedNormal;
    }
    
    // Orthogonalize tangent and bitangent
    displacedTangent = normalize(displacedTangent - dot(displacedTangent, displacedNormal) * displacedNormal);
    displacedBitangent = cross(displacedNormal, displacedTangent) * vWorldTangent.w;
    
    return mat3(displacedTangent, displacedBitangent, displacedNormal);
}

// Get TBN matrix based on user preference
mat3 getActiveTBNMatrix(vec2 dx, vec2 dy) {
    if (uUseSmoothTBN) {
        // Use smooth interpolated TBN from vertex shader
        return mat3(
            normalize(vSmoothWorldTangent),
            normalize(vSmoothWorldBitangent),
            normalize(vSmoothWorldNormal)
        );
    } else {
        // Use physically accurate displaced TBN
        return getDisplacedTBNMatrix(dx, dy);
    }
}

// Helper function to get total surface height (vertex displacement + detail displacement)
float getTotalSurfaceHeight(vec2 texCoords, vec2 dx, vec2 dy) {
    float vertexHeight = textureGrad(uVertexDisplacementMap, texCoords, dx, dy).r * uVertexDisplacementScale;
    float detailHeight = textureGrad(uDisplacementMap, texCoords, dx, dy).r * uDisplacementScale;
    float totalScale = uVertexDisplacementScale + uDisplacementScale;
    // Avoid division by zero when scales are zero
    if (totalScale < 0.001) {
        return 0.5; // Return neutral height when no displacement
    }
    return (vertexHeight + detailHeight) / totalScale;
}

// Helper function to get displacement height from 0 to uDisplacementScale
float simpleGetTotalSurfaceHeight(vec2 texCoords, vec2 dx, vec2 dy) {
    return textureGrad(uDisplacementMap, texCoords, dx, dy).r * uDisplacementScale ;
}

vec3 simpleParallaxOcclusionMap(vec3 V, vec2 dx, vec2 dy) {
    // Use a fixed number of layers for simplicity
    const float numLayers = 32.0;
    
    // Early exit for very steep viewing angles to prevent artifacts
    float viewAngle = abs(V.z);
    if (viewAngle < 0.05) {
        return vec3(vUv, 1.0);
    }
    
    // Reduce parallax effect at glancing angles to prevent warping
    float parallaxAttenuation = smoothstep(0.05, 0.3, viewAngle);
    
    // Standard parallax calculation with angle attenuation
    vec2 P = V.xy / max(viewAngle, 0.1) * uDisplacementScale * parallaxAttenuation;
    vec2 deltaTexCoords = P / numLayers;

    // Standard POM ray marching
    vec2 currentTexCoords = vUv;
    float currentLayerDepth = 0.0;
    float layerDepth = 1.0 / numLayers;
    
    // March through layers until we find intersection
    vec2 prevTexCoords = currentTexCoords;
    float prevLayerDepth = currentLayerDepth;
    
    for(float i = 0.0; i < numLayers; i += 1.0) {
        float currentDepthMapValue = 1.0 - textureGrad(uDisplacementMap, currentTexCoords, dx, dy).r;
        
        if(currentLayerDepth > currentDepthMapValue) {
            break;
        }
        
        prevTexCoords = currentTexCoords;
        prevLayerDepth = currentLayerDepth;
        
        currentTexCoords -= deltaTexCoords;
        currentLayerDepth += layerDepth;
    }

    // Binary search refinement
    const int numRefinementSteps = 8;
    for(int i = 0; i < numRefinementSteps; i++) {
        vec2 midTexCoords = mix(currentTexCoords, prevTexCoords, 0.5);
        float midLayerDepth = mix(currentLayerDepth, prevLayerDepth, 0.5);
        float midDepthMapValue = 1.0 - textureGrad(uDisplacementMap, midTexCoords, dx, dy).r;

        if (midLayerDepth > midDepthMapValue) {
            currentTexCoords = midTexCoords;
            currentLayerDepth = midLayerDepth;
        } else {
            prevTexCoords = midTexCoords;
            prevLayerDepth = midLayerDepth;
        }
    }

    // Final linear interpolation
    float afterDepth = (1.0 - textureGrad(uDisplacementMap, currentTexCoords, dx, dy).r) - currentLayerDepth;
    float beforeDepth = (1.0 - textureGrad(uDisplacementMap, prevTexCoords, dx, dy).r) - prevLayerDepth;
    float weight = afterDepth / (afterDepth - beforeDepth + 1e-8);
    vec2 finalTexCoords = mix(currentTexCoords, prevTexCoords, weight);

    // Check bounds and set alpha
    float alpha = 1.0;
    if (finalTexCoords.x < 0.0 || finalTexCoords.x > 1.0 || finalTexCoords.y < 0.0 || finalTexCoords.y > 1.0) {
        alpha = 0.0;
    }

    return vec3(finalTexCoords, alpha);
}

vec3 parallaxOcclusionMap(vec3 V, vec2 dx, vec2 dy) {
    // Determine number of layers based on view angle for performance
    const float minLayers = 16.0;
    const float maxLayers = 32.0*8.0;
    float numLayers = mix(maxLayers, minLayers, abs(dot(vec3(0.0, 0.0, 1.0), V)));

    float layerDepth = 1.0 / numLayers;
    vec2 P = V.xy / V.z * (uVertexDisplacementScale + uDisplacementScale);
    vec2 deltaTexCoords = P / numLayers;

    // Coarse search to find an interval containing the intersection
    vec2  currentTexCoords = vUv;
    float currentLayerHeight = 1.0;
    float currentDepthMapValue = getTotalSurfaceHeight(currentTexCoords, dx, dy);

    while(currentDepthMapValue < currentLayerHeight) {
        currentLayerHeight -= layerDepth;
        currentTexCoords -= deltaTexCoords;
        currentDepthMapValue = getTotalSurfaceHeight(currentTexCoords, dx, dy);
    }

    // Refined search using binary search (Interval Mapping)
    vec2 prevTexCoords = currentTexCoords + deltaTexCoords;
    float prevLayerHeight = currentLayerHeight + layerDepth;
    const int numRefinementSteps = 8;
    for(int i = 0; i < numRefinementSteps; i++) {
        vec2 midTexCoords = mix(currentTexCoords, prevTexCoords, 0.5);
        float midLayerHeight = mix(currentLayerHeight, prevLayerHeight, 0.5);
        float midDepthMapValue = getTotalSurfaceHeight(midTexCoords, dx, dy);

        if (midDepthMapValue < midLayerHeight) {
            prevTexCoords = midTexCoords;
            prevLayerHeight = midLayerHeight;
        } else {
            currentTexCoords = midTexCoords;
            currentLayerHeight = midLayerHeight;
        }
    }

    // Final linear interpolation on the highly refined interval
    float afterDepth = getTotalSurfaceHeight(currentTexCoords, dx, dy) - currentLayerHeight;
    float beforeDepth = getTotalSurfaceHeight(prevTexCoords, dx, dy) - prevLayerHeight;
    float weight = afterDepth / (afterDepth - beforeDepth);
    vec2 finalTexCoords = mix(currentTexCoords, prevTexCoords, weight);

    float alpha = 1.0;
    if (finalTexCoords.x < 0.0 || finalTexCoords.x > 1.0 || finalTexCoords.y < 0.0 || finalTexCoords.y > 1.0) {
        alpha = 0.0;
    }

    return vec3(finalTexCoords, alpha);
}

float getShadow(vec3 surfacePos, vec3 tangentLightDir, vec2 dx, vec2 dy) {
    if (tangentLightDir.z <= 0.0) return 0.0;
    float shadow = 0.0;
    const int numSamples = 32;
    float rayStep = 1.0 / float(numSamples);
    vec2 texStep = rayStep * (tangentLightDir.xy / tangentLightDir.z) * (uDisplacementScale + uVertexDisplacementScale);
    float currentRayHeight = surfacePos.z + rayStep;
    vec2 currentTexCoords = surfacePos.xy + texStep;
    for (int i = 0; i < numSamples; i++) {
        if (currentRayHeight > 1.0 || currentTexCoords.x < 0.0 || currentTexCoords.x > 1.0 || currentTexCoords.y < 0.0 || currentTexCoords.y > 1.0) break;
        float heightAtSample = getTotalSurfaceHeight(currentTexCoords, dx, dy);
        if (currentRayHeight < heightAtSample) {
            shadow += 1.0;
        }
        currentRayHeight += rayStep;
        currentTexCoords += texStep;
    }
    return 1.0 - min(shadow / uShadowHardness, 1.0);
}

void main() {
    vec3 worldViewDir = normalize(uCameraPosition - vWorldPosition);
    vec2 dx = dFdx(vUv);
    vec2 dy = dFdy(vUv);
    
    // Use active TBN matrix (smooth or physically accurate)
    mat3 tbnMatrix = getActiveTBNMatrix(dx, dy);
    vec3 tangentViewDir = normalize(transpose(tbnMatrix) * worldViewDir);
    
    // Check if we need parallax mapping at all
    float totalDisplacementScale = uVertexDisplacementScale + uDisplacementScale;
    vec2 parallaxUv;
    float alpha = 1.0;
    
    if (totalDisplacementScale < 0.001) {
        // No displacement, use original UVs
        parallaxUv = vUv;
    } else {
        // Apply parallax occlusion mapping
        vec3 pomResult = simpleParallaxOcclusionMap(tangentViewDir, dx, dy);
        parallaxUv = pomResult.xy;
        alpha = pomResult.z;
    }

    if (alpha < 0.5) {
        discard;
    }

    vec3 tangentNormal = textureGrad(uNormalMap, parallaxUv, dx, dy).rgb * 2.0 - 1.0;
    vec3 worldNormal = normalize(tbnMatrix * tangentNormal);
    vec4 diffuseColor = textureGrad(uDiffuseMap, parallaxUv, dx, dy);

    float height = getTotalSurfaceHeight(parallaxUv, dx, dy);
    vec3 tangentSurfacePos = vec3(parallaxUv, height);
    vec3 tangentLightDir = normalize(transpose(tbnMatrix) * uLightDirection);
    float shadow;
    if (!uEnableShadows || totalDisplacementScale < 0.001) {
        // Shadows disabled or no displacement, no self-shadowing
        shadow = 1.0;
    } else {
        shadow = getShadow(tangentSurfacePos, tangentLightDir, dx, dy);
    }

    // Debug mode visualization
    if (uDebugMode > 0) {
        vec3 debugColor = vec3(0.0);
        // Use the same displacement-aware TBN matrix for debug visualization
        vec3 T = tbnMatrix[0]; // Tangent
        vec3 B = tbnMatrix[1]; // Bitangent  
        vec3 N = tbnMatrix[2]; // Normal
        
        if (uDebugMode == 1) {
            // Visualize Tangent (Red channel dominant)
            debugColor = T * 0.5 + 0.5; // Remap from [-1,1] to [0,1]
        } else if (uDebugMode == 2) {
            // Visualize Bitangent (Green channel dominant)
            debugColor = B * 0.5 + 0.5; // Remap from [-1,1] to [0,1]
        } else if (uDebugMode == 3) {
            // Visualize Normal (Blue channel dominant)
            debugColor = N * 0.5 + 0.5; // Remap from [-1,1] to [0,1]
        } else if (uDebugMode == 4) {
            // Visualize View Direction in tangent space
            debugColor = tangentViewDir * 0.5 + 0.5; // Remap from [-1,1] to [0,1]
        } else if (uDebugMode == 5) {
            // Visualize Parallax UV offset
            vec2 uvOffset = parallaxUv - vUv;
            debugColor = vec3(uvOffset * 10.0, 0.0); // Scale up offset for visibility
        } else if (uDebugMode == 6) {
            // Visualize Height Map (inverted for depth)
            float height = 1.0 - textureGrad(uDisplacementMap, parallaxUv, dx, dy).r;
            debugColor = vec3(height);
        }
        
        gl_FragColor = vec4(debugColor, alpha);
        return;
    }

    vec3 worldLightDir = normalize(uLightDirection);
    float diff = max(dot(worldNormal, worldLightDir), 0.0);
    vec3 ambient = vec3(0.1);
    vec3 lighting = (ambient * shadow) + (diffuseColor.rgb * diff * shadow);

    gl_FragColor = vec4(lighting, alpha);
    // gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);
} 