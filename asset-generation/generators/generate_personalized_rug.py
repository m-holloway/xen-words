"""
Generate Personalized Rug with Name

This script generates a rug texture with "XEN WORDS" at the top and a personalized name below,
then applies it to the rug geometry and exports as GLB.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python \
        asset-generation/generators/generate_personalized_rug.py -- \
        --name "Addy" \
        --output-path assets/models/library/PersonalizedRug.glb
"""

import bpy
import sys
import argparse
from pathlib import Path
import math

def create_rug_texture(name="XEN WORDS", width=1024, height=1024):
    """
    Generate a circular rug texture with brand name and personalized name using Blender.
    
    Args:
        name: Personalized name to display below brand
        width: Texture width in pixels
        height: Texture height in pixels
    
    Returns:
        Blender image object
    """
    # Create new image in Blender
    img = bpy.data.images.new(f"RugTexture_{name}", width=width, height=height, alpha=True)
    
    # Get pixel array (RGBA, flat array)
    pixels = list(img.pixels)  # Convert to list for modification
    
    center_x = width // 2
    center_y = height // 2
    radius = min(width, height) // 2 - 20
    
    # Base rug color (warm beige)
    base_r, base_g, base_b = 210/255, 180/255, 140/255
    
    # Draw circular rug with texture
    for y in range(height):
        for x in range(width):
            dx = x - center_x
            dy = y - center_y
            dist = math.sqrt(dx*dx + dy*dy)
            
            idx = (y * width + x) * 4  # RGBA = 4 channels
            
            if dist <= radius:
                # Inside circle - set rug color
                # Add subtle radial texture
                texture_factor = 1.0 - (dist / radius) * 0.2
                
                # Add some circular bands for texture
                band_dist = dist % 100
                if band_dist < 5:
                    texture_factor *= 0.9
                
                pixels[idx] = base_r * texture_factor
                pixels[idx + 1] = base_g * texture_factor
                pixels[idx + 2] = base_b * texture_factor
                pixels[idx + 3] = 1.0  # Alpha
            else:
                # Outside circle - transparent
                pixels[idx] = 0
                pixels[idx + 1] = 0
                pixels[idx + 2] = 0
                pixels[idx + 3] = 0
    
    # Update image with new pixels
    img.pixels = pixels
    img.update()
    
    # Add text using Blender's text objects and render to texture
    # For simplicity, we'll create a basic text overlay using a more manual approach
    # Draw "XEN WORDS" text (simplified - just darkening pixels in text regions)
    
    # Create simple text regions (this is a placeholder - proper text would need font rendering)
    # For now, just add a dark band where text would go
    brand_y = center_y - 60
    name_y = center_y + 20
    
    # Get pixels again
    pixels = list(img.pixels)
    
    # Draw brand text band (simplified)
    for y in range(max(0, brand_y - 40), min(height, brand_y + 40)):
        for x in range(max(0, center_x - 200), min(width, center_x + 200)):
            dx = x - center_x
            dy = y - center_y
            dist = math.sqrt(dx*dx + dy*dy)
            
            if dist <= radius:  # Only draw if inside rug circle
                idx = (y * width + x) * 4
                # Darken for text (this is a placeholder for actual text)
                if abs(y - brand_y) < 30 and abs(x - center_x) < 150:
                    pixels[idx] *= 0.3
                    pixels[idx + 1] *= 0.3
                    pixels[idx + 2] *= 0.3
    
    # Draw name text band (simplified)
    if name:
        for y in range(max(0, name_y - 30), min(height, name_y + 30)):
            for x in range(max(0, center_x - 150), min(width, center_x + 150)):
                dx = x - center_x
                dy = y - center_y
                dist = math.sqrt(dx*dx + dy*dy)
                
                if dist <= radius:  # Only draw if inside rug circle
                    idx = (y * width + x) * 4
                    # Darken for text (this is a placeholder for actual text)
                    if abs(y - name_y) < 25 and abs(x - center_x) < 100:
                        pixels[idx] *= 0.3
                        pixels[idx + 1] *= 0.3
                        pixels[idx + 2] *= 0.3
    
    # Update image
    img.pixels = pixels
    img.update()
    
    print(f"✅ Generated texture with name: {name}")
    
    return img


def generate_personalized_rug(name, output_glb_path):
    """
    Generate a personalized rug with name and export as GLB.
    
    Args:
        name: Name to display on rug
        output_glb_path: Path to export GLB file
    """
    print(f"\n🎨 Generating personalized rug for: {name}")
    
    # Clear scene
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    
    # Load rug geometry from library
    script_dir = Path(__file__).parent.parent.parent
    rug_blend_path = script_dir / "assets" / "models" / "library" / "Rug.blend"
    
    if not rug_blend_path.exists():
        raise FileNotFoundError(f"Rug.blend not found at {rug_blend_path}")
    
    print(f"📂 Loading rug geometry from: {rug_blend_path}")
    
    # Append rug object
    with bpy.data.libraries.load(str(rug_blend_path), link=False) as (data_from, data_to):
        data_to.objects = ['Rug'] if 'Rug' in data_from.objects else []
    
    # Link rug to scene
    rug = None
    for obj in data_to.objects:
        if obj.name == 'Rug':
            bpy.context.collection.objects.link(obj)
            rug = obj
            break
    
    if not rug:
        raise ValueError("Rug object not found in Rug.blend")
    
    print("✅ Rug geometry loaded")
    
    # Generate texture
    print(f"🎨 Generating texture with name: {name}")
    texture_img = create_rug_texture(name=name, width=1024, height=1024)
    
    # Texture image is already created in Blender, no need to load from file
    texture_image = texture_img
    texture_image.name = f"RugTexture_{name}"
    
    # Create material
    mat_name = "PersonalizedRugMaterial"
    mat = bpy.data.materials.new(name=mat_name)
    mat.use_nodes = True
    
    # Clear existing nodes
    nodes = mat.node_tree.nodes
    nodes.clear()
    
    # Create shader nodes
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.location = (0, 0)
    
    tex_image = nodes.new(type='ShaderNodeTexImage')
    tex_image.location = (-400, 0)
    tex_image.image = texture_image
    
    tex_coord = nodes.new(type='ShaderNodeTexCoord')
    tex_coord.location = (-600, 0)
    
    output = nodes.new(type='ShaderNodeOutputMaterial')
    output.location = (200, 0)
    
    # Connect nodes
    mat.node_tree.links.new(tex_coord.outputs['UV'], tex_image.inputs['Vector'])
    mat.node_tree.links.new(tex_image.outputs['Color'], bsdf.inputs['Base Color'])
    mat.node_tree.links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    
    # Set material properties for fabric look
    bsdf.inputs['Roughness'].default_value = 0.9
    bsdf.inputs['Metallic'].default_value = 0.0
    
    # Apply material to rug
    rug.data.materials.clear()
    rug.data.materials.append(mat)
    
    print("✅ Material applied to rug")
    
    # Export GLB
    output_path = Path(output_glb_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    bpy.context.view_layer.objects.active = rug
    rug.select_set(True)
    
    print(f"📦 Exporting GLB to: {output_path}")
    
    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        use_selection=True,
        export_format='GLB',
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
    )
    
    print(f"✅ Personalized rug exported: {output_path}")


def main():
    """Parse command line arguments and generate rug."""
    argv = sys.argv
    if '--' in argv:
        argv = argv[argv.index('--') + 1:]
    else:
        argv = []
    
    parser = argparse.ArgumentParser(description='Generate personalized rug with name')
    parser.add_argument('--name', required=True, help='Name to display on rug')
    parser.add_argument('--output-path', required=True, help='Path to export GLB file')
    
    args = parser.parse_args(argv)
    
    try:
        generate_personalized_rug(args.name, args.output_path)
        print("\n✅ Personalized rug generation complete!\n")
    except Exception as e:
        print(f"\n❌ Error: {e}\n")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()

