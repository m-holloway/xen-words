"""
Apply Personalized Texture to Rug

This script loads a rug from Rug.blend, applies an external PNG texture,
and exports it as a GLB file. This allows runtime texture generation in Flutter
and dynamic GLB creation with the texture baked in.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python \
        asset-generation/generators/apply_rug_texture.py -- \
        --texture-path /path/to/texture.png \
        --output-path /path/to/output.glb
"""

import bpy
import sys
import argparse
from pathlib import Path

def apply_texture_to_rug(texture_path, output_glb_path=None):
    """
    Load rug, apply texture, and optionally export GLB.
    
    Args:
        texture_path: Path to PNG texture file
        output_glb_path: Optional path to export GLB (if None, just applies texture)
    
    Returns:
        The rug object with texture applied
    """
    # Clear scene
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    
    # Load rug from library
    script_dir = Path(__file__).parent.parent.parent  # Go up to project root
    rug_blend_path = script_dir / "assets" / "models" / "library" / "Rug.blend"
    
    if not rug_blend_path.exists():
        raise FileNotFoundError(f"Rug.blend not found at {rug_blend_path}")
    
    # Append rug object from library file
    with bpy.data.libraries.load(str(rug_blend_path), link=False) as (data_from, data_to):
        data_to.objects = ['Rug'] if 'Rug' in data_from.objects else []
    
    # Link rug to current scene
    rug = None
    for obj in data_to.objects:
        if obj.name == 'Rug':
            bpy.context.collection.objects.link(obj)
            rug = obj
            break
    
    if not rug:
        raise ValueError("Rug object not found in Rug.blend")
    
    # Load texture image
    if not Path(texture_path).exists():
        raise FileNotFoundError(f"Texture not found at {texture_path}")
    
    texture_image = bpy.data.images.load(texture_path)
    texture_image.name = "RugTexture"
    
    # Get or create material
    mat_name = "RugMaterial"
    if mat_name in bpy.data.materials:
        mat = bpy.data.materials[mat_name]
    else:
        mat = bpy.data.materials.new(name=mat_name)
        mat.use_nodes = True
    
    # Clear existing nodes
    nodes = mat.node_tree.nodes
    nodes.clear()
    
    # Create Principled BSDF
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.location = (0, 0)
    
    # Create Image Texture node
    tex_image = nodes.new(type='ShaderNodeTexImage')
    tex_image.location = (-400, 0)
    tex_image.image = texture_image
    
    # Create Texture Coordinate node
    tex_coord = nodes.new(type='ShaderNodeTexCoord')
    tex_coord.location = (-600, 0)
    
    # Create Output node
    output = nodes.new(type='ShaderNodeOutputMaterial')
    output.location = (200, 0)
    
    # Connect nodes
    mat.node_tree.links.new(tex_coord.outputs['UV'], tex_image.inputs['Vector'])
    mat.node_tree.links.new(tex_image.outputs['Color'], bsdf.inputs['Base Color'])
    mat.node_tree.links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    
    # Set material properties
    bsdf.inputs['Roughness'].default_value = 0.9
    bsdf.inputs['Metallic'].default_value = 0.0
    
    # Apply material to rug
    rug.data.materials.clear()
    rug.data.materials.append(mat)
    
    print(f"✅ Applied texture '{texture_path}' to rug")
    
    # Export GLB if path provided
    if output_glb_path:
        # Select rug
        bpy.context.view_layer.objects.active = rug
        rug.select_set(True)
        
        # Export GLB
        output_glb_path = Path(output_glb_path)
        output_glb_path.parent.mkdir(parents=True, exist_ok=True)
        
        bpy.ops.export_scene.gltf(
            filepath=str(output_glb_path),
            use_selection=True,
            export_format='GLB',
        )
        
        print(f"✅ Exported GLB: {output_glb_path}")
    
    return rug

def main():
    """Parse command line arguments and apply texture."""
    # Parse arguments (Blender passes everything after --)
    argv = sys.argv
    if '--' in argv:
        argv = argv[argv.index('--') + 1:]
    else:
        argv = []
    
    parser = argparse.ArgumentParser(description='Apply texture to rug and export GLB')
    parser.add_argument('--texture-path', required=True, help='Path to PNG texture file')
    parser.add_argument('--output-path', help='Path to export GLB file (optional)')
    
    args = parser.parse_args(argv)
    
    try:
        apply_texture_to_rug(args.texture_path, args.output_path)
        print("\n✅ Rug texture application complete\n")
    except Exception as e:
        print(f"\n❌ Error: {e}\n")
        sys.exit(1)

if __name__ == "__main__":
    main()

