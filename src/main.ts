import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import GUI from 'lil-gui';
import vertexShader from './shaders/POM-vertex.glsl?raw';
import fragmentShader from './shaders/POM-fragment.glsl?raw';
import vertexShaderDense from './shaders/standard-vertex.glsl?raw';
import fragmentShaderDense from './shaders/standard-fragment.glsl?raw';

// ===== GUI PERSISTENCE SYSTEM =====
// This module handles saving/loading GUI controls to localStorage
// To remove: delete this section and remove calls to GuiPersistence methods
class GuiPersistence {
    private static readonly STORAGE_KEY = 'pom-demo-settings';
    private static readonly VERSION = '1.0';
    
    // Define default values for all controls (excluding camera angle)
    private static readonly defaults = {
        displayMode: 'Custom Shader',
        parallaxScale: 0.075,
        displacementScale: 0.2,
        parallaxOffset: 0,
        textureRepeat: 10.0,
        dynamicLayers: true,
        pomMethod: 0,
        wireframe: false,
        debugMode: 0,
        lightDirectionX: 1.0,
        lightDirectionY: 1.0,
        enableShadows: true,
        shadowHardness: 8.0,
        useSmoothTBN: true,
        showFpsMonitor: false,
        showRenderStats: false
    };

    static saveSettings(settings: Partial<typeof GuiPersistence.defaults>): void {
        try {
            const data = {
                version: this.VERSION,
                settings: { ...this.defaults, ...settings }
            };
            localStorage.setItem(this.STORAGE_KEY, JSON.stringify(data));
        } catch (error) {
            console.warn('Failed to save GUI settings:', error);
        }
    }

    static loadSettings(): typeof GuiPersistence.defaults {
        try {
            const stored = localStorage.getItem(this.STORAGE_KEY);
            if (!stored) return { ...this.defaults };
            
            const data = JSON.parse(stored);
            if (data.version !== this.VERSION) {
                console.log('Settings version mismatch, using defaults');
                return { ...this.defaults };
            }
            
            return { ...this.defaults, ...data.settings };
        } catch (error) {
            console.warn('Failed to load GUI settings:', error);
            return { ...this.defaults };
        }
    }

    static resetToDefaults(): typeof GuiPersistence.defaults {
        try {
            localStorage.removeItem(this.STORAGE_KEY);
        } catch (error) {
            console.warn('Failed to clear settings:', error);
        }
        return { ...this.defaults };
    }

    static getDefaults(): typeof GuiPersistence.defaults {
        return { ...this.defaults };
    }
}
// ===== END GUI PERSISTENCE SYSTEM =====

// Performance monitoring class
class PerformanceMonitor {
    private frames: number = 0;
    private lastTime: number = 0;
    private fps: number = 0;
    private frameTime: number = 0;
    private minFps: number = Infinity;
    private maxFps: number = 0;
    private fpsHistory: number[] = [];
    private frameTimeHistory: number[] = [];
    private historyLength: number = 60; // Keep 60 samples
    private updateInterval: number = 100; // Update display every 100ms
    private lastUpdate: number = 0;
    private container!: HTMLElement;
    private gpuPanel?: HTMLElement;

    constructor() {
        this.createUI();
        this.lastTime = performance.now();
    }

    private createUI(): void {
        // Create performance overlay
        this.container = document.createElement('div');
        this.container.style.cssText = `
            position: fixed;
            top: 200px;
            left: 10px;
            background: rgba(0, 0, 0, 0.8);
            color: #00ff00;
            padding: 10px;
            border-radius: 5px;
            font-family: 'Courier New', monospace;
            font-size: 12px;
            z-index: 1000;
            min-width: 200px;
            backdrop-filter: blur(4px);
            border: 1px solid rgba(0, 255, 0, 0.3);
        `;
        document.body.appendChild(this.container);

        // Check if GPU timing extension is available
        const canvas = document.createElement('canvas');
        const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
        if (gl) {
            const ext = gl.getExtension('EXT_disjoint_timer_query_webgl2') || 
                       gl.getExtension('EXT_disjoint_timer_query');
            if (ext) {
                this.gpuPanel = document.createElement('div');
                this.gpuPanel.style.marginTop = '5px';
                this.gpuPanel.style.paddingTop = '5px';
                this.gpuPanel.style.borderTop = '1px solid rgba(0, 255, 0, 0.3)';
                this.container.appendChild(this.gpuPanel);
            }
        }
    }

    update(): void {
        const now = performance.now();
        this.frameTime = now - this.lastTime;
        this.frames++;

        // Update FPS calculation
        if (now - this.lastUpdate >= this.updateInterval) {
            this.fps = Math.round((this.frames * 1000) / (now - this.lastUpdate));
            
            // Update min/max FPS
            if (this.fps > 0) {
                this.minFps = Math.min(this.minFps, this.fps);
                this.maxFps = Math.max(this.maxFps, this.fps);
            }

            // Update history
            this.fpsHistory.push(this.fps);
            this.frameTimeHistory.push(this.frameTime);
            
            if (this.fpsHistory.length > this.historyLength) {
                this.fpsHistory.shift();
                this.frameTimeHistory.shift();
            }

            this.updateDisplay();
            this.frames = 0;
            this.lastUpdate = now;
        }

        this.lastTime = now;
    }

    private updateDisplay(): void {
        const avgFps = this.fpsHistory.length > 0 ? 
            Math.round(this.fpsHistory.reduce((a, b) => a + b, 0) / this.fpsHistory.length) : 0;
        const avgFrameTime = this.frameTimeHistory.length > 0 ?
            (this.frameTimeHistory.reduce((a, b) => a + b, 0) / this.frameTimeHistory.length).toFixed(2) : '0.00';

        // Get memory info if available
        let memoryInfo = '';
        if ('memory' in performance && (performance as any).memory) {
            const memory = (performance as any).memory;
            const usedMB = Math.round(memory.usedJSHeapSize / 1048576);
            const totalMB = Math.round(memory.totalJSHeapSize / 1048576);
            const limitMB = Math.round(memory.jsHeapSizeLimit / 1048576);
            memoryInfo = `
                <div style="margin-top: 5px; padding-top: 5px; border-top: 1px solid rgba(0, 255, 0, 0.3);">
                    <div><strong>Memory:</strong></div>
                    <div>Used: ${usedMB} MB</div>
                    <div>Total: ${totalMB} MB</div>
                    <div>Limit: ${limitMB} MB</div>
                </div>
            `;
        }

        // Get GPU info if available
        let gpuInfo = '';
        if (this.gpuPanel) {
            gpuInfo = `
                <div><strong>GPU:</strong></div>
                <div>Timer queries supported</div>
            `;
        }

        this.container.innerHTML = `
            <div><strong>Performance Monitor</strong></div>
            <div style="margin-top: 5px;">
                <div>FPS: <span style="color: ${this.getFpsColor(this.fps)}">${this.fps}</span></div>
                <div>Avg FPS: ${avgFps}</div>
                <div>Min: ${this.minFps === Infinity ? 0 : this.minFps} / Max: ${this.maxFps}</div>
                <div>Frame Time: ${this.frameTime.toFixed(2)}ms</div>
                <div>Avg Frame Time: ${avgFrameTime}ms</div>
            </div>
            ${memoryInfo}
            ${this.gpuPanel ? gpuInfo : ''}
        `;

        if (this.gpuPanel && gpuInfo) {
            this.gpuPanel.innerHTML = gpuInfo;
        }
    }

    private getFpsColor(fps: number): string {
        if (fps >= 60) return '#00ff00'; // Green
        if (fps >= 30) return '#ffff00'; // Yellow
        if (fps >= 15) return '#ff8800'; // Orange
        return '#ff0000'; // Red
    }

    reset(): void {
        this.frames = 0;
        this.minFps = Infinity;
        this.maxFps = 0;
        this.fpsHistory = [];
        this.frameTimeHistory = [];
        this.lastTime = performance.now();
        this.lastUpdate = this.lastTime;
    }

    setVisible(visible: boolean): void {
        this.container.style.display = visible ? 'block' : 'none';
    }

    destroy(): void {
        if (this.container && this.container.parentNode) {
            this.container.parentNode.removeChild(this.container);
        }
    }
}

// Rendering statistics tracker
class RenderStats {
    private info!: HTMLElement;
    
    constructor() {
        this.createUI();
    }

    private createUI(): void {
        this.info = document.createElement('div');
        this.info.style.cssText = `
            position: fixed;
            top: 10px;
            left: 10px;
            background: rgba(0, 0, 0, 0.8);
            color: #00aaff;
            padding: 10px;
            border-radius: 5px;
            font-family: 'Courier New', monospace;
            font-size: 12px;
            z-index: 1000;
            backdrop-filter: blur(4px);
            border: 1px solid rgba(0, 170, 255, 0.3);
        `;
        document.body.appendChild(this.info);
    }

    update(renderer: THREE.WebGLRenderer): void {
        const info = renderer.info;
        
        this.info.innerHTML = `
            <div><strong>Render Statistics</strong></div>
            <div style="margin-top: 5px;">
                <div>Geometry: ${info.memory.geometries}</div>
                <div>Textures: ${info.memory.textures}</div>
                <div>Draw Calls: ${info.render.calls}</div>
                <div>Triangles: ${info.render.triangles.toLocaleString()}</div>
                <div>Points: ${info.render.points.toLocaleString()}</div>
                <div>Lines: ${info.render.lines.toLocaleString()}</div>
                <div>Programs: ${info.programs?.length || 0}</div>
            </div>
        `;
    }

    setVisible(visible: boolean): void {
        this.info.style.display = visible ? 'block' : 'none';
    }

    destroy(): void {
        if (this.info && this.info.parentNode) {
            this.info.parentNode.removeChild(this.info);
        }
    }
}

// Initial displacement values
const INITIAL_DISPLACEMENT_SCALE = 0.075;
const INITIAL_VERTEX_DISPLACEMENT_SCALE = 0.2;

// Load saved settings or use defaults
const savedSettings = GuiPersistence.loadSettings();

// Initialize performance monitoring (hidden by default)
const performanceMonitor = new PerformanceMonitor();
const renderStats = new RenderStats();

// Apply saved visibility settings to performance monitors
performanceMonitor.setVisible(savedSettings.showFpsMonitor);
renderStats.setVisible(savedSettings.showRenderStats);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.001, 100);
const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setSize(window.innerWidth, window.innerHeight);
document.body.appendChild(renderer.domElement);

const maxAnisotropy = renderer.capabilities.getMaxAnisotropy();

// Set initial camera angle to 45 degrees
const initialAngle = 88; // degrees
const radius = 0.5; // Zoomed in closer
camera.position.y = Math.sin(-initialAngle * Math.PI / 180) * radius;
camera.position.z = Math.cos(-initialAngle * Math.PI / 180) * radius;
camera.position.x = 0.0;
camera.lookAt(0, 0, 0);

const geometry = new THREE.PlaneGeometry(1, 1, 1024/4, 1024/4);
geometry.computeTangents();

const loader = new THREE.TextureLoader();
const diffuseMap = loader.load('/gray_rocks/gray_rocks_diff_2k.jpg');
diffuseMap.anisotropy = maxAnisotropy;
diffuseMap.wrapS = THREE.RepeatWrapping;
diffuseMap.wrapT = THREE.RepeatWrapping;
const normalMap = loader.load('/gray_rocks/gray_rocks_nor_gl_2k.jpg');
normalMap.anisotropy = maxAnisotropy;
normalMap.wrapS = THREE.RepeatWrapping;
normalMap.wrapT = THREE.RepeatWrapping;
const displacementMap = loader.load('/gray_rocks/gray_rocks_disp_2k.jpg');
displacementMap.anisotropy = maxAnisotropy;
displacementMap.wrapS = THREE.RepeatWrapping;
displacementMap.wrapT = THREE.RepeatWrapping;
const vertexDisplacementMap = loader.load('/displacement/heightmap.png');
vertexDisplacementMap.anisotropy = maxAnisotropy;
vertexDisplacementMap.wrapS = THREE.ClampToEdgeWrapping;
vertexDisplacementMap.wrapT = THREE.ClampToEdgeWrapping;

const material = new THREE.ShaderMaterial({
    vertexShader,
    fragmentShader,
    transparent: true,
    uniforms: {
        uDiffuseMap: { value: diffuseMap },
        uNormalMap: { value: normalMap },
        uDisplacementMap: { value: displacementMap },
        uVertexDisplacementMap: { value: vertexDisplacementMap },
        uDisplacementScale: { value: savedSettings.parallaxScale / savedSettings.textureRepeat },
        uVertexDisplacementScale: { value: savedSettings.displacementScale },
        uParallaxOffset: { value: savedSettings.parallaxOffset },
        uLightDirection: { value: new THREE.Vector3(savedSettings.lightDirectionX, savedSettings.lightDirectionY, 1.0) },
        uCameraPosition: { value: new THREE.Vector3() },
        uShadowHardness: { value: savedSettings.shadowHardness },
        uDebugMode: { value: savedSettings.debugMode },
        uEnableShadows: { value: savedSettings.enableShadows },
        uUseDynamicLayers: { value: savedSettings.dynamicLayers },
        uPOMMethod: { value: savedSettings.pomMethod },
        uTextureRepeat: { value: savedSettings.textureRepeat },
        uUseSmoothTBN: { value: savedSettings.useSmoothTBN },
    },
});

const plane = new THREE.Mesh(geometry, material);
// Center the POM mesh
plane.position.x = 0;
scene.add(plane);

// Create standard mesh for comparison (initially hidden)
const denseGeometry = new THREE.PlaneGeometry(1, 1, 512, 512); // High-density geometry
denseGeometry.computeTangents();

const denseMaterial = new THREE.ShaderMaterial({
    vertexShader: vertexShaderDense,
    fragmentShader: fragmentShaderDense,
    uniforms: {
        uDiffuseMap: { value: diffuseMap },
        uNormalMap: { value: normalMap },
        uDisplacementMap: { value: displacementMap },
        uVertexDisplacementMap: { value: vertexDisplacementMap },
        uDisplacementScale: { value: savedSettings.parallaxScale / savedSettings.textureRepeat },
        uVertexDisplacementScale: { value: savedSettings.displacementScale },
        uLightDirection: { value: new THREE.Vector3(savedSettings.lightDirectionX, savedSettings.lightDirectionY, 1.0) },
        uCameraPosition: { value: new THREE.Vector3() },
        uTextureRepeat: { value: savedSettings.textureRepeat },
    },
});

const densePlane = new THREE.Mesh(denseGeometry, denseMaterial);
// Center the standard mesh and apply saved settings
densePlane.position.x = 0;
scene.add(densePlane);

// Apply wireframe setting from saved settings
material.wireframe = savedSettings.wireframe;
denseMaterial.wireframe = savedSettings.wireframe;

// Apply display mode from saved settings
if (savedSettings.displayMode === 'Standard Mesh') {
    plane.visible = false;
    densePlane.visible = true;
} else {
    plane.visible = true;
    densePlane.visible = false;
}

const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;

const gui = new GUI();

// Display mode control
const displayControl = {
    mode: savedSettings.displayMode
};

const displayModeOptions = {
    'Custom Shader': 'Custom Shader',
    'Standard Mesh': 'Standard Mesh'
};

gui.add(displayControl, 'mode', displayModeOptions).name('Display Mode').onChange((value: string) => {
    if (value === 'Custom Shader') {
        plane.visible = true;
        densePlane.visible = false;
    } else if (value === 'Standard Mesh') {
        plane.visible = false;
        densePlane.visible = true;
    }
    // Save setting
    GuiPersistence.saveSettings({ displayMode: value });
});

// Helper function to get currently active material
function getActiveMaterial(): THREE.ShaderMaterial {
    return plane.visible ? material : denseMaterial;
}

// Helper function to sync uniforms to both materials
function syncUniformToBoth(uniformName: string, value: any): void {
    material.uniforms[uniformName].value = value;
    denseMaterial.uniforms[uniformName].value = value;
}

// Store the raw GUI values
let rawParallaxScale = savedSettings.parallaxScale;
let textureRepeat = savedSettings.textureRepeat;

// Helper function to update parallax scale with texture repeat compensation
function updateParallaxScale(): void {
    const adjustedScale = rawParallaxScale / textureRepeat;
    syncUniformToBoth('uDisplacementScale', adjustedScale);
}

// Set initial adjusted parallax scale
updateParallaxScale();

gui.add({ value: rawParallaxScale }, 'value', 0, 0.2, 0.001).name('Parallax Scale').onChange((value: number) => {
    rawParallaxScale = value;
    updateParallaxScale();
    GuiPersistence.saveSettings({ parallaxScale: value });
});
gui.add(material.uniforms.uVertexDisplacementScale, 'value', 0, 0.5, 0.001).name('Displacement Scale').onChange((value: number) => {
    syncUniformToBoth('uVertexDisplacementScale', value);
    GuiPersistence.saveSettings({ displacementScale: value });
});

gui.add(material.uniforms.uParallaxOffset, 'value', -1.0, 1.0, 0.01).name('Parallax Offset').onChange((value: number) => {
    GuiPersistence.saveSettings({ parallaxOffset: value });
});

gui.add({ value: textureRepeat }, 'value', 1.0, 150.0, 0.1).name('Texture Repeat').onChange((value: number) => {
    textureRepeat = value;
    syncUniformToBoth('uTextureRepeat', value);
    updateParallaxScale(); // Update parallax scale when texture repeat changes
    GuiPersistence.saveSettings({ textureRepeat: value });
});

// Add debug mode control
const debugModeOptions = {
    'Normal Rendering': 0,
    'Tangent Vectors (T)': 1,
    'Bitangent Vectors (B)': 2,
    'Normal Vectors (N)': 3,
    'View Direction': 4,
    'Parallax UV Offset': 5,
    'Height Map': 6
};



// Add dynamic layers control
gui.add(material.uniforms.uUseDynamicLayers, 'value').name('Dynamic Layers (vs Fixed)').onChange((value: boolean) => {
    GuiPersistence.saveSettings({ dynamicLayers: value });
});

// Add POM method selection
const pomMethodOptions = {
    'Standard POM': 0,
    'Terrain POM': 1
};
gui.add(material.uniforms.uPOMMethod, 'value', pomMethodOptions).name('POM Method').onChange((value: number) => {
    GuiPersistence.saveSettings({ pomMethod: value });
});

// Add camera angle control
const cameraControl = {
    angle: initialAngle
};

function updateCameraPosition(angle: number) {
    const angleRad = -angle * Math.PI / 180;
    camera.position.x = 0.0;
    camera.position.y = Math.sin(angleRad) * radius;
    camera.position.z = Math.cos(angleRad) * radius;
    camera.lookAt(0, 0, 0);
}

// Add wireframe toggle
const wireframeControl = {
    wireframe: savedSettings.wireframe
};
gui.add(wireframeControl, 'wireframe').name('Wireframe').onChange((value: boolean) => {
    material.wireframe = value;
    denseMaterial.wireframe = value;
    GuiPersistence.saveSettings({ wireframe: value });
});

gui.add(material.uniforms.uDebugMode, 'value', debugModeOptions).name('Debug Mode').onChange((value: number) => {
    GuiPersistence.saveSettings({ debugMode: value });
});

const lightFolder = gui.addFolder('Lighting');
lightFolder.close(); // Close folder by default
lightFolder.add(cameraControl, 'angle', -90, 90, 1).name('Camera Angle (°)').onChange((value: number) => {
    updateCameraPosition(value);
});
lightFolder.add(material.uniforms.uLightDirection.value, 'x', -1, 1, 0.01).name('Light Direction X').onChange((value: number) => {
    material.uniforms.uLightDirection.value.x = value;
    denseMaterial.uniforms.uLightDirection.value.x = value;
    GuiPersistence.saveSettings({ lightDirectionX: value });
});
lightFolder.add(material.uniforms.uLightDirection.value, 'y', -1, 1, 0.01).name('Light Direction Y').onChange((value: number) => {
    material.uniforms.uLightDirection.value.y = value;
    denseMaterial.uniforms.uLightDirection.value.y = value;
    GuiPersistence.saveSettings({ lightDirectionY: value });
});
lightFolder.add(material.uniforms.uEnableShadows, 'value').name('Enable Shadows').onChange((value: boolean) => {
    GuiPersistence.saveSettings({ enableShadows: value });
});
lightFolder.add(material.uniforms.uShadowHardness, 'value', 1.0, 32.0, 1.0).name('Shadow Hardness').onChange((value: number) => {
    GuiPersistence.saveSettings({ shadowHardness: value });
});
lightFolder.add(material.uniforms.uUseSmoothTBN, 'value').name('Use Smooth TBN').onChange((value: boolean) => {
    GuiPersistence.saveSettings({ useSmoothTBN: value });
});

// Performance monitoring controls
const perfFolder = gui.addFolder('Performance Monitor');
perfFolder.close(); // Close folder by default
const perfControls = {
    showFpsMonitor: savedSettings.showFpsMonitor,
    showRenderStats: savedSettings.showRenderStats,
    resetStats: () => {
        performanceMonitor.reset();
        console.log('Performance statistics reset');
    }
};

perfFolder.add(perfControls, 'showFpsMonitor').name('Show FPS Monitor').onChange((value: boolean) => {
    performanceMonitor.setVisible(value);
    GuiPersistence.saveSettings({ showFpsMonitor: value });
});

perfFolder.add(perfControls, 'showRenderStats').name('Show Render Stats').onChange((value: boolean) => {
    renderStats.setVisible(value);
    GuiPersistence.saveSettings({ showRenderStats: value });
});

perfFolder.add(perfControls, 'resetStats').name('Reset Statistics');

// Add reset button at the bottom
const resetControls = {
    resetToDefaults: () => {
        // Reset to defaults
        const defaults = GuiPersistence.resetToDefaults();
        
        // Update all GUI controls
        displayControl.mode = defaults.displayMode;
        rawParallaxScale = defaults.parallaxScale;
        textureRepeat = defaults.textureRepeat;
        wireframeControl.wireframe = defaults.wireframe;
        perfControls.showFpsMonitor = defaults.showFpsMonitor;
        perfControls.showRenderStats = defaults.showRenderStats;
        
        // Update material uniforms
        material.uniforms.uVertexDisplacementScale.value = defaults.displacementScale;
        material.uniforms.uParallaxOffset.value = defaults.parallaxOffset;
        material.uniforms.uDebugMode.value = defaults.debugMode;
        material.uniforms.uUseDynamicLayers.value = defaults.dynamicLayers;
        material.uniforms.uPOMMethod.value = defaults.pomMethod;
        material.uniforms.uLightDirection.value.x = defaults.lightDirectionX;
        material.uniforms.uLightDirection.value.y = defaults.lightDirectionY;
        material.uniforms.uEnableShadows.value = defaults.enableShadows;
        material.uniforms.uShadowHardness.value = defaults.shadowHardness;
        material.uniforms.uUseSmoothTBN.value = defaults.useSmoothTBN;
        
        // Sync uniforms to both materials
        syncUniformToBoth('uVertexDisplacementScale', defaults.displacementScale);
        syncUniformToBoth('uTextureRepeat', defaults.textureRepeat);
        updateParallaxScale();
        syncUniformToBoth('uLightDirection', new THREE.Vector3(defaults.lightDirectionX, defaults.lightDirectionY, 1.0));
        
        // Update wireframe
        material.wireframe = defaults.wireframe;
        denseMaterial.wireframe = defaults.wireframe;
        
        // Update display mode
        if (defaults.displayMode === 'Standard Mesh') {
            plane.visible = false;
            densePlane.visible = true;
        } else {
            plane.visible = true;
            densePlane.visible = false;
        }
        
        // Update performance monitors
        performanceMonitor.setVisible(defaults.showFpsMonitor);
        renderStats.setVisible(defaults.showRenderStats);
        
        console.log('GUI controls reset to defaults');
    }
};

gui.add(resetControls, 'resetToDefaults').name('🔄 Reset to Defaults');

window.addEventListener('resize', () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
});

function animate() {
    requestAnimationFrame(animate);
    
    // Update performance monitoring
    performanceMonitor.update();
    renderStats.update(renderer);
    
    controls.update();
    
    // Only update camera position for the currently visible mesh (performance optimization)
    if (plane.visible) {
    material.uniforms.uCameraPosition.value.copy(camera.position);
    } else {
    denseMaterial.uniforms.uCameraPosition.value.copy(camera.position);
    }
    
    renderer.render(scene, camera);
}

animate();
