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

uniform bool uEnableShadows; // true=shadows enabled, false=shadows disabled
uniform bool uUseDynamicLayers; // true=dynamic layers based on view angle, false=fixed layers
uniform int uPOMMethod; // 0=standard, 1=terrain, 2=full
uniform float uTextureRepeat; // Number of times to repeat the parallax textures


// Get TBN matrix - always use smooth interpolated TBN from vertex shader
mat3 getActiveTBNMatrix(vec2 dx, vec2 dy) {
    return mat3(
        normalize(vSmoothWorldTangent),
        normalize(vSmoothWorldBitangent),
        normalize(vSmoothWorldNormal)
    );
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
float terrainGetTotalSurfaceHeight(vec2 texCoords, vec2 dx, vec2 dy) {
    vec2 repeatedCoords = texCoords * uTextureRepeat;
    vec2 repeatedDx = dx * uTextureRepeat;
    vec2 repeatedDy = dy * uTextureRepeat;
    return (textureGrad(uDisplacementMap, repeatedCoords, repeatedDx, repeatedDy).r) * uDisplacementScale ;
}

// Standard basic parallax occlusion mapping - simplest implementation
vec3 standardParallaxOcclusionMap(vec3 V, vec2 dx, vec2 dy) {
    // Determine number of layers - dynamic or fixed
    float numLayers;
    if (uUseDynamicLayers) {
        // Dynamic layers based on view angle for performance
        const float minLayers = 8.0;
        const float maxLayers = 32.0*4.0;
        numLayers = mix(maxLayers, minLayers, abs(dot(vec3(0.0, 0.0, 1.0), V)));
    } else {
        // Fixed number of layers
        numLayers = 16.0; // Lower for standard version
    }
    
    // Basic parallax offset calculation
    vec2 P = V.xy / max(V.z, 0.001) * uDisplacementScale;
    vec2 deltaTexCoords = P / numLayers;
    
    // Simple ray marching
    vec2 currentTexCoords = vUv;
    float currentLayerHeight = 1.0;
    float layerDepth = 1.0 / numLayers;
    
    // Basic coarse search to find intersection interval
    vec2 prevTexCoords = currentTexCoords;
    float prevLayerHeight = currentLayerHeight;
    
    for(float i = 0.0; i < numLayers; i += 1.0) {
        vec2 repeatedCoords = currentTexCoords * uTextureRepeat;
        vec2 repeatedDx = dx * uTextureRepeat;
        vec2 repeatedDy = dy * uTextureRepeat;
        float currentDepthMapValue = textureGrad(uDisplacementMap, repeatedCoords, repeatedDx, repeatedDy).r;
        
        if (currentDepthMapValue >= currentLayerHeight) {
            break;
        }
        
        // Store previous values for refinement
        prevTexCoords = currentTexCoords;
        prevLayerHeight = currentLayerHeight;
        
        currentLayerHeight -= layerDepth;
        currentTexCoords -= deltaTexCoords;
    }
    
    // Binary search refinement (Interval Mapping)
    const int numRefinementSteps = 6; // Less refinement for standard version
    for(int i = 0; i < numRefinementSteps; i++) {
        vec2 midTexCoords = mix(currentTexCoords, prevTexCoords, 0.5);
        float midLayerHeight = mix(currentLayerHeight, prevLayerHeight, 0.5);
        vec2 midRepeatedCoords = midTexCoords * uTextureRepeat;
        vec2 midRepeatedDx = dx * uTextureRepeat;
        vec2 midRepeatedDy = dy * uTextureRepeat;
        float midDepthMapValue = textureGrad(uDisplacementMap, midRepeatedCoords, midRepeatedDx, midRepeatedDy).r;

        if (midDepthMapValue < midLayerHeight) {
            prevTexCoords = midTexCoords;
            prevLayerHeight = midLayerHeight;
        } else {
            currentTexCoords = midTexCoords;
            currentLayerHeight = midLayerHeight;
        }
    }

    // Final linear interpolation for smooth transition
    vec2 afterRepeatedCoords = currentTexCoords * uTextureRepeat;
    vec2 afterRepeatedDx = dx * uTextureRepeat;
    vec2 afterRepeatedDy = dy * uTextureRepeat;
    float afterDepth = textureGrad(uDisplacementMap, afterRepeatedCoords, afterRepeatedDx, afterRepeatedDy).r - currentLayerHeight;
    
    vec2 beforeRepeatedCoords = prevTexCoords * uTextureRepeat;
    vec2 beforeRepeatedDx = dx * uTextureRepeat;
    vec2 beforeRepeatedDy = dy * uTextureRepeat;
    float beforeDepth = textureGrad(uDisplacementMap, beforeRepeatedCoords, beforeRepeatedDx, beforeRepeatedDy).r - prevLayerHeight;
    float weight = afterDepth / (afterDepth - beforeDepth);
    vec2 finalTexCoords = mix(currentTexCoords, prevTexCoords, weight);
    
    float alpha = 1.0;
    // if (finalTexCoords.x < 0.0 || finalTexCoords.x > 1.0 || 
    //     finalTexCoords.y < 0.0 || finalTexCoords.y > 1.0) {
    //     alpha = 0.0;
    // }
    
    return vec3(finalTexCoords, alpha);
}

vec3 terrainParallaxOcclusionMap(vec3 V, vec2 dx, vec2 dy) {
    // Determine number of layers - dynamic or fixed
    float numLayers;
    if (uUseDynamicLayers) {
        // Dynamic layers based on view angle for performance
        const float minLayers = 16.0;
        const float maxLayers = 64.0; // Lower max for terrain version
        numLayers = mix(maxLayers, minLayers, abs(dot(vec3(0.0, 0.0, 1.0), V)));
    } else {
        // Fixed number of layers
        numLayers = 32.0;
    }
    
    // Smooth V.z influence for stable parallax
    float smoothVz = smoothstep(0.0, 1.5, abs(V.z)); // Smooth S-curve transition
    float reducedVz = mix(0.5, 1.0, smoothVz); // Blend with smoother transition
    // vec2 P = V.xy / reducedVz * uDisplacementScale;
    vec2 P = V.xy / reducedVz * uDisplacementScale;
    vec2 deltaTexCoords = P / numLayers;

    // Step along the displaced surface
    vec2 currentTexCoords = vUv;
    float currentLayerHeight = uDisplacementScale; // Start from max height
    float currentDepthMapValue = terrainGetTotalSurfaceHeight(currentTexCoords, dx, dy);

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
        float nextDepthMapValue = terrainGetTotalSurfaceHeight(nextTexCoords, dx, dy);
        
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
        float midDepthMapValue = terrainGetTotalSurfaceHeight(midTexCoords, dx, dy);

        if (midDepthMapValue < midLayerHeight) {
            prevTexCoords = midTexCoords;
            prevLayerHeight = midLayerHeight;
        } else {
            currentTexCoords = midTexCoords;
            currentLayerHeight = midLayerHeight;
        }
    }

    // Final linear interpolation on the highly refined interval
    float afterDepth = terrainGetTotalSurfaceHeight(currentTexCoords, dx, dy) - currentLayerHeight;
    float beforeDepth = terrainGetTotalSurfaceHeight(prevTexCoords, dx, dy) - prevLayerHeight;
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
    // Determine number of layers - dynamic or fixed
    float numLayers;
    if (uUseDynamicLayers) {
        // Dynamic layers based on view angle for performance
        const float minLayers = 16.0;
        const float maxLayers = 32.0*8.0;
        numLayers = mix(maxLayers, minLayers, abs(dot(vec3(0.0, 0.0, 1.0), V)));
    } else {
        // Fixed number of layers
        numLayers = 32.0;
    }

    float layerDepth = 1.0 / numLayers;
    vec2 P = V.xy / V.z * uDisplacementScale; // Only use detail displacement for parallax
    vec2 deltaTexCoords = P / numLayers;

    // Coarse search to find an interval containing the intersection
    vec2  currentTexCoords = vUv;
    float currentLayerHeight = 1.0;
    float currentDepthMapValue = textureGrad(uDisplacementMap, currentTexCoords, dx, dy).r;

    while(currentDepthMapValue < currentLayerHeight) {
        currentLayerHeight -= layerDepth;
        currentTexCoords -= deltaTexCoords;
        currentDepthMapValue = textureGrad(uDisplacementMap, currentTexCoords, dx, dy).r;
    }

    // Refined search using binary search (Interval Mapping)
    vec2 prevTexCoords = currentTexCoords + deltaTexCoords;
    float prevLayerHeight = currentLayerHeight + layerDepth;
    const int numRefinementSteps = 8;
    for(int i = 0; i < numRefinementSteps; i++) {
        vec2 midTexCoords = mix(currentTexCoords, prevTexCoords, 0.5);
        float midLayerHeight = mix(currentLayerHeight, prevLayerHeight, 0.5);
        float midDepthMapValue = textureGrad(uDisplacementMap, midTexCoords, dx, dy).r;

        if (midDepthMapValue < midLayerHeight) {
            prevTexCoords = midTexCoords;
            prevLayerHeight = midLayerHeight;
        } else {
            currentTexCoords = midTexCoords;
            currentLayerHeight = midLayerHeight;
        }
    }

    // Final linear interpolation on the highly refined interval
    float afterDepth = textureGrad(uDisplacementMap, currentTexCoords, dx, dy).r - currentLayerHeight;
    float beforeDepth = textureGrad(uDisplacementMap, prevTexCoords, dx, dy).r - prevLayerHeight;
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
    vec2 texStep = rayStep * (tangentLightDir.xy / max(tangentLightDir.z, 0.001)) * uDisplacementScale;
    float currentRayHeight = surfacePos.z + rayStep;
    vec2 currentTexCoords = surfacePos.xy + texStep;
    
    // Use repeated coordinates and derivatives for shadow sampling
    vec2 repeatedDx = dx * uTextureRepeat;
    vec2 repeatedDy = dy * uTextureRepeat;
    
    for (int i = 0; i < numSamples; i++) {
        if (currentRayHeight > 1.0 || currentTexCoords.x < -0.5 || currentTexCoords.x > 1.5 || currentTexCoords.y < -0.5 || currentTexCoords.y > 1.5) break;
        
        // Sample height using repeated coordinates
        vec2 repeatedTexCoords = currentTexCoords * uTextureRepeat;
        float heightAtSample = textureGrad(uDisplacementMap, repeatedTexCoords, repeatedDx, repeatedDy).r;
        
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
    vec2 parallaxUv;
    float alpha = 1.0;
    
    if (uDisplacementScale < 0.001) {
        // No parallax displacement, use original UVs (skip POM calculation)
        parallaxUv = vUv;
    } else {
        // Apply selected parallax occlusion mapping method
        vec3 pomResult;
        if (uPOMMethod == 0) {
            // Standard POM - simplest implementation
            pomResult = standardParallaxOcclusionMap(tangentViewDir, dx, dy);
        } else if (uPOMMethod == 1) {
            // Terrain POM - with surface slope adjustments
            pomResult = terrainParallaxOcclusionMap(tangentViewDir, dx, dy);
        } else {
            // Full POM - with binary search refinement
            pomResult = parallaxOcclusionMap(tangentViewDir, dx, dy);
        }
        parallaxUv = pomResult.xy;
        alpha = pomResult.z;
    }

    if (alpha < 0.5) {
        discard;
    }

    vec2 repeatedParallaxUv = parallaxUv * uTextureRepeat;
    vec2 repeatedDx = dx * uTextureRepeat;
    vec2 repeatedDy = dy * uTextureRepeat;
    
    vec3 tangentNormal = textureGrad(uNormalMap, repeatedParallaxUv, repeatedDx, repeatedDy).rgb * 2.0 - 1.0;
    vec3 worldNormal = normalize(tbnMatrix * tangentNormal);
    vec4 diffuseColor = textureGrad(uDiffuseMap, repeatedParallaxUv, repeatedDx, repeatedDy);

    // Calculate surface position in tangent space for shadows using repeated coordinates
    float height = textureGrad(uDisplacementMap, repeatedParallaxUv, repeatedDx, repeatedDy).r;
    vec3 tangentSurfacePos = vec3(parallaxUv, height);
    vec3 tangentLightDir = normalize(transpose(tbnMatrix) * uLightDirection);
    float shadow;
    if (!uEnableShadows || uDisplacementScale < 0.001) {
        // Shadows disabled or no parallax displacement, no self-shadowing
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
            // Visualize Height Map
            float height = terrainGetTotalSurfaceHeight(parallaxUv, dx, dy) / uDisplacementScale;
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