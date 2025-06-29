import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import GUI from 'lil-gui';
import vertexShader from './shaders/POM-vertex.glsl?raw';
import fragmentShader from './shaders/POM-fragment.glsl?raw';
import vertexShaderDense from './shaders/standard-vertex.glsl?raw';
import fragmentShaderDense from './shaders/standard-fragment.glsl?raw';

// Default values for controls
const DEFAULT_PARALLAX_SCALE = 0.075;
const DEFAULT_DISPLACEMENT_SCALE = 0.2;
const DEFAULT_TEXTURE_REPEAT = 129.9;
const DEFAULT_ACTIVE_RADIUS = 3.0;
const DEFAULT_MIN_LAYERS = 8.0;
const DEFAULT_MAX_LAYERS = 32.0;
const DEFAULT_DEBUG_MODE = 0;
const DEFAULT_SHADOW_MODE = false;

// GPU Performance monitoring class for shader timing
class GPUPerformanceMonitor {
    private gl: WebGL2RenderingContext | WebGLRenderingContext;
    private timerExt: any = null;
    private queries: any[] = [];
    private queryIndex: number = 0;
    private maxQueries: number = 10; // Ring buffer of queries
    private gpuTimes: number[] = [];
    private lastGpuTime: number = 0;
    private avgGpuTime: number = 0;
    private container!: HTMLElement;
    private isSupported: boolean = false;

    constructor(renderer: THREE.WebGLRenderer) {
        const context = renderer.getContext();
        this.gl = context;
        
        // Try to get timer query extension
        this.timerExt = this.gl.getExtension('EXT_disjoint_timer_query_webgl2') || 
                       this.gl.getExtension('EXT_disjoint_timer_query');
        
        this.isSupported = !!this.timerExt;
        
        if (this.isSupported) {
            // Pre-create queries using the extension or WebGL2 context
            for (let i = 0; i < this.maxQueries; i++) {
                let query;
                if (this.timerExt.createQueryEXT) {
                    // WebGL1 extension
                    query = this.timerExt.createQueryEXT();
                } else if ((this.gl as WebGL2RenderingContext).createQuery) {
                    // WebGL2
                    query = (this.gl as WebGL2RenderingContext).createQuery();
                }
                if (query) this.queries.push(query);
            }
        }
        
        this.createUI();
    }

    private createUI(): void {
        this.container = document.createElement('div');
        this.container.style.cssText = `
            position: fixed;
            top: 380px;
            left: 10px;
            background: rgba(0, 0, 0, 0.8);
            color: #ff8800;
            padding: 10px;
            border-radius: 5px;
            font-family: 'Courier New', monospace;
            font-size: 12px;
            z-index: 1000;
            min-width: 200px;
            backdrop-filter: blur(4px);
            border: 1px solid rgba(255, 136, 0, 0.3);
        `;
        document.body.appendChild(this.container);
        this.updateDisplay();
    }

    startTiming(): void {
        if (!this.isSupported || this.queries.length === 0) return;
        
        const query = this.queries[this.queryIndex];
        if (this.timerExt.beginQueryEXT) {
            // WebGL1 extension
            this.timerExt.beginQueryEXT(this.timerExt.TIME_ELAPSED_EXT, query);
        } else {
            // WebGL2
            (this.gl as WebGL2RenderingContext).beginQuery(this.timerExt.TIME_ELAPSED_EXT, query);
        }
    }

    endTiming(): void {
        if (!this.isSupported) return;
        
        if (this.timerExt.endQueryEXT) {
            // WebGL1 extension
            this.timerExt.endQueryEXT(this.timerExt.TIME_ELAPSED_EXT);
        } else {
            // WebGL2
            (this.gl as WebGL2RenderingContext).endQuery(this.timerExt.TIME_ELAPSED_EXT);
        }
        this.queryIndex = (this.queryIndex + 1) % this.queries.length;
    }

    update(): void {
        if (!this.isSupported) return;

        // Check for completed queries
        for (let i = 0; i < this.queries.length; i++) {
            const query = this.queries[i];
            let available: boolean;
            
            if (this.timerExt.getQueryObjectEXT) {
                // WebGL1 extension
                available = this.timerExt.getQueryObjectEXT(query, this.timerExt.QUERY_RESULT_AVAILABLE_EXT);
            } else {
                // WebGL2
                available = (this.gl as WebGL2RenderingContext).getQueryParameter(query, (this.gl as WebGL2RenderingContext).QUERY_RESULT_AVAILABLE);
            }
            
            if (available) {
                let timeElapsed: number;
                
                if (this.timerExt.getQueryObjectEXT) {
                    // WebGL1 extension
                    timeElapsed = this.timerExt.getQueryObjectEXT(query, this.timerExt.QUERY_RESULT_EXT);
                } else {
                    // WebGL2
                    timeElapsed = (this.gl as WebGL2RenderingContext).getQueryParameter(query, (this.gl as WebGL2RenderingContext).QUERY_RESULT);
                }
                
                const timeMs = timeElapsed / 1000000; // Convert nanoseconds to milliseconds
                
                this.lastGpuTime = timeMs;
                this.gpuTimes.push(timeMs);
                
                if (this.gpuTimes.length > 30) {
                    this.gpuTimes.shift();
                }
                
                this.avgGpuTime = this.gpuTimes.reduce((a, b) => a + b, 0) / this.gpuTimes.length;
                this.updateDisplay();
            }
        }
    }

    private updateDisplay(): void {
        if (!this.isSupported) {
            this.container.innerHTML = `
                <div><strong>GPU Performance</strong></div>
                <div style="color: #ff4444;">Timer queries not supported</div>
            `;
            return;
        }

        this.container.innerHTML = `
            <div><strong>GPU Performance</strong></div>
            <div style="margin-top: 5px;">
                <div>GPU Time: ${this.lastGpuTime.toFixed(3)}ms</div>
                <div>Avg GPU: ${this.avgGpuTime.toFixed(3)}ms</div>
                <div>Samples: ${this.gpuTimes.length}</div>
            </div>
        `;
    }

    setVisible(visible: boolean): void {
        this.container.style.display = visible ? 'block' : 'none';
    }

    reset(): void {
        this.gpuTimes = [];
        this.lastGpuTime = 0;
        this.avgGpuTime = 0;
        this.updateDisplay();
    }

    destroy(): void {
        if (this.container && this.container.parentNode) {
            this.container.parentNode.removeChild(this.container);
        }
        
        // Clean up WebGL queries
        for (const query of this.queries) {
            if (this.timerExt.deleteQueryEXT) {
                // WebGL1 extension
                this.timerExt.deleteQueryEXT(query);
            } else {
                // WebGL2
                (this.gl as WebGL2RenderingContext).deleteQuery(query);
            }
        }
        this.queries = [];
    }
}

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
            top: 160px;
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

// Initialize performance monitoring (hidden by default)
const performanceMonitor = new PerformanceMonitor();
const renderStats = new RenderStats();

// Wait for renderer to be created before initializing GPU monitor
let gpuMonitor: GPUPerformanceMonitor;

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.001, 100);
const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setSize(window.innerWidth, window.innerHeight);
document.body.appendChild(renderer.domElement);

// Initialize GPU monitor after renderer is created
gpuMonitor = new GPUPerformanceMonitor(renderer);

// Apply saved visibility settings to all performance monitors
performanceMonitor.setVisible(true);
renderStats.setVisible(true);
gpuMonitor.setVisible(true);

const maxAnisotropy = renderer.capabilities.getMaxAnisotropy();

// Set initial camera angle to 45 degrees
const initialAngle = 81; // degrees
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
        uDisplacementScale: { value: DEFAULT_PARALLAX_SCALE / DEFAULT_TEXTURE_REPEAT },
        uVertexDisplacementScale: { value: DEFAULT_DISPLACEMENT_SCALE },
        uParallaxOffset: { value: 0.0 },
        uActiveRadius: { value: DEFAULT_ACTIVE_RADIUS },
        uMinLayers: { value: DEFAULT_MIN_LAYERS },
        uMaxLayers: { value: DEFAULT_MAX_LAYERS },
        uLightDirection: { value: new THREE.Vector3(0.0, 1.0, 1.0) },
        uCameraPosition: { value: new THREE.Vector3() },
        uShadowHardness: { value: 16.0 },
        uDebugMode: { value: DEFAULT_DEBUG_MODE },
        uEnableShadows: { value: DEFAULT_SHADOW_MODE },
        uUseDynamicLayers: { value: true },
        uPOMMethod: { value: 1 },
        uTextureRepeat: { value: DEFAULT_TEXTURE_REPEAT },
        uUseSmoothTBN: { value: false },
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
        uDisplacementScale: { value: DEFAULT_PARALLAX_SCALE / DEFAULT_TEXTURE_REPEAT },
        uVertexDisplacementScale: { value: DEFAULT_DISPLACEMENT_SCALE },
        uActiveRadius: { value: DEFAULT_ACTIVE_RADIUS },
        uMinLayers: { value: DEFAULT_MIN_LAYERS },
        uMaxLayers: { value: DEFAULT_MAX_LAYERS },
        uLightDirection: { value: new THREE.Vector3(0.0, 1.0, 1.0) },
        uCameraPosition: { value: new THREE.Vector3() },
        uTextureRepeat: { value: DEFAULT_TEXTURE_REPEAT },
        uEnableShadows: { value: DEFAULT_SHADOW_MODE },
    },
});

const densePlane = new THREE.Mesh(denseGeometry, denseMaterial);
// Center the standard mesh and apply saved settings
densePlane.position.x = 0;
scene.add(densePlane);

// Apply wireframe setting from saved settings
material.wireframe = false;
denseMaterial.wireframe = false;

// Apply display mode from saved settings
if (true) {
    plane.visible = true;
    densePlane.visible = false;
} else {
    plane.visible = false;
    densePlane.visible = true;
}

const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;

const gui = new GUI();

// Display mode control
const displayControl = {
    mode: 'Custom Shader'
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
let rawParallaxScale = DEFAULT_PARALLAX_SCALE;
let textureRepeat = DEFAULT_TEXTURE_REPEAT;

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
});
const displacementControls = {
    displacementScale: DEFAULT_DISPLACEMENT_SCALE,
    parallaxOffset: 0.0,
    activeRadius: DEFAULT_ACTIVE_RADIUS,
    minLayers: DEFAULT_MIN_LAYERS,
    maxLayers: DEFAULT_MAX_LAYERS
};

gui.add(displacementControls, 'displacementScale', 0, 0.5, 0.001).name('Displacement Scale').onChange((value: number) => {
    material.uniforms.uVertexDisplacementScale.value = value;
    syncUniformToBoth('uVertexDisplacementScale', value);
});

gui.add(displacementControls, 'parallaxOffset', -1.0, 1.0, 0.01).name('Parallax Offset').onChange((value: number) => {
    material.uniforms.uParallaxOffset.value = value;
});

gui.add(displacementControls, 'activeRadius', 0.1, 10.0, 0.1).name('Active Radius').onChange((value: number) => {
    syncUniformToBoth('uActiveRadius', value);
});

gui.add(displacementControls, 'minLayers', 1.0, 32.0, 1.0).name('Min Layers').onChange((value: number) => {
    syncUniformToBoth('uMinLayers', value);
});

gui.add(displacementControls, 'maxLayers', 8.0, 128.0, 1.0).name('Max Layers').onChange((value: number) => {
    syncUniformToBoth('uMaxLayers', value);
});

gui.add({ value: textureRepeat }, 'value', 1.0, 150.0, 0.1).name('Texture Repeat').onChange((value: number) => {
    textureRepeat = value;
    syncUniformToBoth('uTextureRepeat', value);
    updateParallaxScale(); // Update parallax scale when texture repeat changes
});

// Add debug mode control
const debugModeOptions = {
    'Normal Rendering': 0,
    'Tangent Vectors (T)': 1,
    'Bitangent Vectors (B)': 2,
    'Normal Vectors (N)': 3,
    'View Direction': 4,
    'Parallax UV Offset': 5,
    'Height Map': 6,
    'Angle Mask': 7
};

// Add dynamic layers control
const dynamicLayersControl = { enabled: true };
gui.add(dynamicLayersControl, 'enabled').name('Dynamic Layers (vs Fixed)').onChange((value: boolean) => {
    material.uniforms.uUseDynamicLayers.value = value;
});

// Add POM method selection
const pomMethodOptions = {
    'Standard POM': 0,
    'Terrain POM': 1
};
const pomMethodControl = { method: 1 };
gui.add(pomMethodControl, 'method', pomMethodOptions).name('POM Method').onChange((value: number) => {
    material.uniforms.uPOMMethod.value = value;
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
    wireframe: false
};
gui.add(wireframeControl, 'wireframe').name('Wireframe').onChange((value: boolean) => {
    material.wireframe = value;
    denseMaterial.wireframe = value;
});

const debugModeControl = { mode: 0 };
gui.add(debugModeControl, 'mode', debugModeOptions).name('Debug Mode').onChange((value: number) => {
    material.uniforms.uDebugMode.value = value;
});

const lightFolder = gui.addFolder('Lighting');
lightFolder.open(); // Open folder by default
lightFolder.add(cameraControl, 'angle', -90, 90, 1).name('Camera Angle (°)').onChange((value: number) => {
    updateCameraPosition(value);
});
const lightControls = {
    directionX: 0.0,
    directionY: 1.0,
    enableShadows: true,
    shadowHardness: 16.0,
    useSmoothTBN: false
};

lightFolder.add(lightControls, 'directionX', -1, 1, 0.01).name('Light Direction X').onChange((value: number) => {
    material.uniforms.uLightDirection.value.x = value;
    denseMaterial.uniforms.uLightDirection.value.x = value;
});
lightFolder.add(lightControls, 'directionY', -1, 1, 0.01).name('Light Direction Y').onChange((value: number) => {
    material.uniforms.uLightDirection.value.y = value;
    denseMaterial.uniforms.uLightDirection.value.y = value;
});
lightFolder.add(lightControls, 'enableShadows').name('Enable Shadows').onChange((value: boolean) => {
    material.uniforms.uEnableShadows.value = value;
});
lightFolder.add(lightControls, 'shadowHardness', 1.0, 32.0, 1.0).name('Shadow Hardness').onChange((value: number) => {
    material.uniforms.uShadowHardness.value = value;
});
lightFolder.add(lightControls, 'useSmoothTBN').name('Use Smooth TBN').onChange((value: boolean) => {
    material.uniforms.uUseSmoothTBN.value = value;
});

// Performance monitoring controls
const perfFolder = gui.addFolder('Performance Monitor');
perfFolder.open(); // Open folder by default
const perfControls = {
    showFpsMonitor: true,
    showRenderStats: true,
    showGpuMonitor: true,
    resetStats: () => {
        performanceMonitor.reset();
        gpuMonitor.reset();
        console.log('Performance statistics reset');
    }
};

perfFolder.add(perfControls, 'showFpsMonitor').name('Show FPS Monitor').onChange((value: boolean) => {
    performanceMonitor.setVisible(value);
});

perfFolder.add(perfControls, 'showRenderStats').name('Show Render Stats').onChange((value: boolean) => {
    renderStats.setVisible(value);
});

perfFolder.add(perfControls, 'showGpuMonitor').name('Show GPU Performance').onChange((value: boolean) => {
    gpuMonitor.setVisible(value);
});

perfFolder.add(perfControls, 'resetStats').name('Reset Statistics');

// Add reset button at the bottom
const resetControls = {
    resetToDefaults: () => {
        // Reset to defaults
        const defaults = {
            displayMode: true,
            parallaxScale: DEFAULT_PARALLAX_SCALE,
            textureRepeat: DEFAULT_TEXTURE_REPEAT,
            wireframe: false,
            pomMethod: 1,
            debugMode: DEFAULT_DEBUG_MODE,
            dynamicLayers: true,
            displacementScale: DEFAULT_DISPLACEMENT_SCALE,
            parallaxOffset: 0.0,
            activeRadius: DEFAULT_ACTIVE_RADIUS,
            minLayers: DEFAULT_MIN_LAYERS,
            maxLayers: DEFAULT_MAX_LAYERS,
            lightDirectionX: 0.0,
            lightDirectionY: 1.0,
            enableShadows: DEFAULT_SHADOW_MODE,
            shadowHardness: 16.0,
            useSmoothTBN: false,
            showFpsMonitor: true,
            showRenderStats: true,
            showGpuMonitor: true
        };
        
        // Update all GUI controls
        displayControl.mode = defaults.displayMode ? 'Custom Shader' : 'Standard Mesh';
        rawParallaxScale = defaults.parallaxScale;
        textureRepeat = defaults.textureRepeat;
        wireframeControl.wireframe = defaults.wireframe;
        pomMethodControl.method = defaults.pomMethod;
        debugModeControl.mode = defaults.debugMode;
        dynamicLayersControl.enabled = defaults.dynamicLayers;
        displacementControls.displacementScale = defaults.displacementScale;
        displacementControls.parallaxOffset = defaults.parallaxOffset;
        displacementControls.activeRadius = defaults.activeRadius;
        displacementControls.minLayers = defaults.minLayers;
        displacementControls.maxLayers = defaults.maxLayers;
        lightControls.directionX = defaults.lightDirectionX;
        lightControls.directionY = defaults.lightDirectionY;
        lightControls.enableShadows = defaults.enableShadows;
        lightControls.shadowHardness = defaults.shadowHardness;
        lightControls.useSmoothTBN = defaults.useSmoothTBN;
        perfControls.showFpsMonitor = defaults.showFpsMonitor;
        perfControls.showRenderStats = defaults.showRenderStats;
        
        // Update material uniforms
        material.uniforms.uVertexDisplacementScale.value = defaults.displacementScale;
        material.uniforms.uParallaxOffset.value = defaults.parallaxOffset;
        material.uniforms.uActiveRadius.value = defaults.activeRadius;
        material.uniforms.uMinLayers.value = defaults.minLayers;
        material.uniforms.uMaxLayers.value = defaults.maxLayers;
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
        syncUniformToBoth('uActiveRadius', defaults.activeRadius);
        syncUniformToBoth('uMinLayers', defaults.minLayers);
        syncUniformToBoth('uMaxLayers', defaults.maxLayers);
        syncUniformToBoth('uTextureRepeat', defaults.textureRepeat);
        updateParallaxScale();
        syncUniformToBoth('uLightDirection', new THREE.Vector3(defaults.lightDirectionX, defaults.lightDirectionY, 1.0));
        
        // Update wireframe
        material.wireframe = defaults.wireframe;
        denseMaterial.wireframe = defaults.wireframe;
        
        // Update display mode
        if (defaults.displayMode) {
            plane.visible = true;
            densePlane.visible = false;
        } else {
            plane.visible = false;
            densePlane.visible = true;
        }
        
        // Update performance monitors
        performanceMonitor.setVisible(defaults.showFpsMonitor);
        renderStats.setVisible(defaults.showRenderStats);
        gpuMonitor.setVisible(defaults.showGpuMonitor);
        
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
    
    // Start GPU timing
    gpuMonitor.startTiming();
    
    // Update performance monitoring
    performanceMonitor.update();
    renderStats.update(renderer);
    gpuMonitor.update();
    
    controls.update();
    
    // Only update camera position for the currently visible mesh (performance optimization)
    if (plane.visible) {
    material.uniforms.uCameraPosition.value.copy(camera.position);
    } else {
    denseMaterial.uniforms.uCameraPosition.value.copy(camera.position);
    }
    
    renderer.render(scene, camera);
    
    // End GPU timing
    gpuMonitor.endTiming();
}

animate();
