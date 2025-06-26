varying vec2 vUv;
varying vec3 vWorldPosition;
varying vec3 vWorldNormal;
varying vec4 vWorldTangent;

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
    
    // Smooth V.z influence for stable parallax
    float smoothVz = smoothstep(0.0, 1.0, abs(V.z)); // Smooth S-curve transition
    float reducedVz = mix(0.5, 1.0, smoothVz); // Blend with smoother transition
    vec2 P = V.xy / reducedVz * uDisplacementScale;
    vec2 deltaTexCoords = P / numLayers;

    // Step along the displaced surface
    vec2 currentTexCoords = vUv;
    float currentLayerHeight = uDisplacementScale; // Start from max height
    float currentDepthMapValue = simpleGetTotalSurfaceHeight(currentTexCoords, dx, dy);

    // Step through layers, but adjust step size based on surface slope
    vec2 prevTexCoords = vUv;
    float prevLayerHeight = uDisplacementScale;
    
    for(float i = 0.0; i < numLayers; i += 1.0) {
        if(currentDepthMapValue >= currentLayerHeight) break;
        
        // Store previous values for refinement
        prevTexCoords = currentTexCoords;
        prevLayerHeight = currentLayerHeight;
        
        // Sample surface height at next position to get surface slope
        vec2 nextTexCoords = currentTexCoords - deltaTexCoords;
        float nextDepthMapValue = simpleGetTotalSurfaceHeight(nextTexCoords, dx, dy);
        
        // Calculate surface slope and adjust our stepping
        float surfaceSlope = (nextDepthMapValue - currentDepthMapValue);
        
        // Step along the surface contour - adjust layer height based on surface slope
        float dynamicLayerDepth = (uDisplacementScale / numLayers) * (1.0 + surfaceSlope * 2.0);
        currentLayerHeight -= dynamicLayerDepth;
        
        currentTexCoords = nextTexCoords;
        currentDepthMapValue = nextDepthMapValue;
    }

    // Refined search using binary search (Interval Mapping)
    const int numRefinementSteps = 8;
    for(int i = 0; i < numRefinementSteps; i++) {
        vec2 midTexCoords = mix(currentTexCoords, prevTexCoords, 0.5);
        float midLayerHeight = mix(currentLayerHeight, prevLayerHeight, 0.5);
        float midDepthMapValue = simpleGetTotalSurfaceHeight(midTexCoords, dx, dy);

        if (midDepthMapValue < midLayerHeight) {
            prevTexCoords = midTexCoords;
            prevLayerHeight = midLayerHeight;
        } else {
            currentTexCoords = midTexCoords;
            currentLayerHeight = midLayerHeight;
        }
    }

    // Final linear interpolation on the highly refined interval
    float afterDepth = simpleGetTotalSurfaceHeight(currentTexCoords, dx, dy) - currentLayerHeight;
    float beforeDepth = simpleGetTotalSurfaceHeight(prevTexCoords, dx, dy) - prevLayerHeight;
    float weight = afterDepth / (afterDepth - beforeDepth);
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
    
    // Use displacement-aware TBN matrix
    mat3 tbnMatrix = getDisplacedTBNMatrix(dx, dy);
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
    if (totalDisplacementScale < 0.001) {
        // No displacement, no self-shadowing
        shadow = 1.0;
    } else {
        shadow = getShadow(tangentSurfacePos, tangentLightDir, dx, dy);
    }
    // shadow = 1.0;

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
            // Visualize Height Map
            float height = simpleGetTotalSurfaceHeight(parallaxUv, dx, dy) / uDisplacementScale;
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