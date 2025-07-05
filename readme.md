# Radiance Cascades

Real-time 2D global illumination through radiance cascades

## Usage

1. Add the "2D GI" renderer feature to your URP renderer
2. Use a material with the "Sprite (GI)" shader on all objects that should emit or receive global illumination.
3. Objects that emit light should have a variant of the material using the "_GI_EMISSION" keyword enabled (available as a toggle in the inspector).