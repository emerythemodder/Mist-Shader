#define PATH_TRACED_SHADOWS

const int shadowMapResolution = 2048;
const float shadowDistance = 256.0;
const float shadowDistanceRenderMul = 1.0;
const float sunPathRotation = -25.0; // [-45.0 -40.0 -35.0 -30.0 -25.0 -20.0 -15.0 -10.0 -5.0 0.0 5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0]
const float ambientOcclusionLevel = 0.4;
const bool shadowtex0Nearest = true;
const bool shadowtex1Nearest = true;
const bool shadowcolor0Nearest = false;
const float wetnessHalflife = 300.0;
const float drynessHalflife = 70.0;
const float eyeBrightnessHalflife = 8.0;

#define SUBSURFACE_SCATTERING
#define AMBIENT_STRENGTH 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define BLOCKLIGHT_STRENGTH 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define EMISSIVE_STRENGTH 4.0 // [1.0 2.0 3.0 4.0 6.0 8.0]
#define HAND_LIGHT
#define SPAWN_WARNING
#define RT_BLOCK_LIGHTS
#define RT_LIGHT_TRACES 6 // [2 4 6 8 12 16]
#define RT_SHADOW_SOFTNESS 0.2 // [0.0 0.1 0.2 0.3 0.45 0.6]
#define RT_SUN_SOFTNESS 0.05 // [0.0 0.015 0.025 0.035 0.05 0.08 0.12]
#define PATH_TRACING

#define NORMAL_MAPPING
#define PBR_SPECULAR
#define IBL
#define PBR_FORMAT 0 // [0 1]
#define INTEGRATED_PBR
#define PARALLAX
#define POM_DEPTH 0.25 // [0.1 0.15 0.2 0.25 0.35 0.5]
#define POM_DISTANCE 24.0 // [8.0 16.0 24.0 32.0 48.0]
#define POM_STEPS 48 // [16 24 32 48 64]
#define GENERATED_PARALLAX
//#define EMISSIVE_ORES
#define WAVING_PLANTS
#define WAVING_SPEED 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define PLANT_BENDING
#define PLANT_BEND_STRENGTH 1.0 // [0.5 0.75 1.0 1.25 1.5]

#define FLASHLIGHT_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0]

#define WATER_WAVES
#define WAVE_HEIGHT 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0]
#define WAVE_SPEED 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define RAIN_RIPPLES
#define SPLASH_SIMULATION
#define SNOW_COVER
#define FOOTPRINTS
#define SMOOTH_TERRAIN
#define SMOOTH_STRENGTH 0.85 // [0.5 0.65 0.85 1.0]
#define SNOW_GEOMETRY
//#define BIOME_FOG
#define SURF_FOAM
#define WATER_FOAM
#define FOAM_AMOUNT 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0]
#define WATER_GEOMETRY
#define WATER_REFRACTION
#define REFRACTION_STRENGTH 1.0 // [0.25 0.5 1.0 1.5 2.0 3.0]
#define WATER_CAUSTICS
#define CAUSTIC_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define WATER_CLARITY 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0]
#define INTERACTIVE_RIPPLES
#define RIPPLE_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0]
#define RIPPLE_RES 1024
#define RIPPLE_CELLS 16.0

#define SSR
#define SSR_STEPS 32 // [16 24 32 48 64]
#define RAIN_PUDDLES
#define PUDDLE_AMOUNT 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]

#define VOLUMETRIC_LIGHT
#define VL_STEPS 12 // [6 8 12 16 24 32]
#define VL_DENSITY 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0]
#define VOLUMETRIC_CLOUDS
#define CLOUD_STEPS 32 // [16 24 32 40 48]
#define ALTOCUMULUS_CLOUDS
#define CIRRUS_CLOUDS
#define CLOUD_SHADOWS
#define CLOUD_COVERAGE 0.45 // [0.2 0.3 0.4 0.45 0.5 0.6 0.7 0.8]
#define CLOUD_ALTITUDE 640 // [320 480 640 800 1000 1300]
#define STARS
#define SKY_HALOS
#define ECLIPSES
#define BLOOD_MOON
#define METEOR_SHOWERS
#define MILKY_WAY
#define SHOOTING_STARS
#define AURORA
//#define AURORA_ALWAYS
#define RAINBOW
#define LIGHTNING_FLASH
#define FOG_DENSITY 0.0 // [0.0 0.25 0.5 1.0 1.5 2.0 3.0]

#define BLOOM
#define BLOOM_STRENGTH 0.06 // [0.02 0.04 0.06 0.08 0.1 0.15 0.2]
#define AUTO_EXPOSURE
#define EXPOSURE_BIAS 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0]
#define SATURATION 1.05 // [0.8 0.9 1.0 1.05 1.1 1.2 1.3]
#define CONTRAST 1.0 // [0.8 0.9 1.0 1.05 1.1 1.2]
#define VIGNETTE
#define VIGNETTE_STRENGTH 0.35 // [0.1 0.2 0.35 0.5 0.75]
#define TAA
#define CURVED_WORLD
#define CURVATURE_RADIUS 2000 // [500 1000 2000 4000 8000 16000]
#define FXAA
#define PURKINJE
#define LENS_FLARE
#define LENS_RAIN
#define WET_LENS
#define COLD_BREATH
#define VITALS_FX
//#define SNEAK_ZOOM
#define ZOOM_FACTOR 3.0 // [1.5 2.0 3.0 4.0 6.0 8.0]
#define HEAT_HAZE
//#define DEPTH_OF_FIELD
#define DOF_STRENGTH 1.0 // [0.25 0.5 1.0 1.5 2.0 3.0]
//#define MOTION_BLUR
#define MOTION_BLUR_STRENGTH 1.0 // [0.25 0.5 1.0 1.5 2.0]
//#define CHROMATIC_ABERRATION
//#define FILM_GRAIN
#define SHARPENING 0.35 // [0.0 0.15 0.25 0.35 0.5 0.75 1.0]

#define SHADOW_DISTORT 0.85

#ifdef PATH_TRACED_SHADOWS
    #ifdef WORLD_OVERWORLD
        #define USE_SHADOWS
    #endif
#endif
#ifdef VOLUMETRIC_LIGHT
    #ifdef USE_SHADOWS
        #define USE_VOLUMETRIC_LIGHT
    #endif
#endif
#ifdef VOLUMETRIC_CLOUDS
    #ifdef WORLD_OVERWORLD
        #define USE_VOLUMETRIC_CLOUDS
        #ifdef CLOUD_SHADOWS
            #define USE_CLOUD_SHADOWS
        #endif
    #endif
#endif
#ifdef RAIN_PUDDLES
    #ifdef WORLD_OVERWORLD
        #define USE_RAIN_PUDDLES
    #endif
#endif

#ifdef RT_BLOCK_LIGHTS
    #ifdef IMAGE_CAPABLE
        #define USE_RT_LIGHTS
    #endif
#endif
#ifdef SNOW_GEOMETRY
    #define USE_SNOW_GEOMETRY
#endif
#ifdef FOOTPRINTS
    #ifdef IMAGE_CAPABLE
        #define USE_SNOW_TRACKS
    #endif

    #define SNOW_TRACKS_READ
#endif
#ifdef WATER_GEOMETRY
    #define USE_WATER_GEOMETRY
#endif

#ifdef SPLASH_SIMULATION
    #ifdef IMAGE_CAPABLE
        #ifdef WORLD_OVERWORLD
            #define USE_MPM
        #endif
    #endif
#endif

#ifdef IBL
    #ifdef IMAGE_CAPABLE
        #ifdef WORLD_OVERWORLD
            #define USE_IBL
        #endif
    #endif
#endif
#ifdef WATER_FOAM
    #define USE_WATER_FOAM
#endif

#ifdef PLANT_BENDING
    #ifdef IMAGE_CAPABLE
        #define USE_PLANT_BEND
    #endif
    #define PLANT_BEND_READ
#endif
#ifdef USE_RT_LIGHTS

    #ifdef USE_SHADOWS
        #define USE_RT_SUN_SHADOWS
        #define USE_PT_SHADOWS
    #endif

    #define USE_RT_HALF

    #ifdef PATH_TRACING
        #ifdef WORLD_OVERWORLD
            #define USE_PT
        #endif
    #endif
#endif
#ifdef FXAA
    #ifndef TAA
        #define USE_FXAA
    #endif
#endif

#ifdef CURVED_WORLD
    #ifndef VOXY
        #define USE_CURVED_WORLD
    #endif
#endif

#ifndef VOXY
    #ifdef IEXT_ENABLED
        #define USE_ZOOM
    #endif
    #ifdef SNEAK_ZOOM
        #define USE_ZOOM
    #endif
#endif

#ifdef INTERACTIVE_RIPPLES
    #ifdef IMAGE_CAPABLE
        #define USE_RIPPLES
    #endif
#endif
