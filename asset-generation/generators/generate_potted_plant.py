"""
Procedural Potted Plant Composer

Composes a complete potted plant from Pot + Foliage + Dirt.
This demonstrates compositional asset creation.

Usage:
    blender --background --python generate_potted_plant.py
"""

import bpy
import bmesh
import math
from pathlib import Path

# ============================================================================
# PARAMETERS - Adjust these to change the composition
# ============================================================================

COMPOSITION_CONFIG = {
    # Component paths (relative to library/)
    'pot_file': 'Pot.blend',
    'foliage_file': 'Foliage.blend',
    
    # Positioning
    'foliage_z_offset': 0.32,   # Height to place foliage base (meters)
    'foliage_scale': 1.0,         # Scale factor for foliage
    
    # Dirt surface
    'dirt_z': 0.329,              # Height of dirt surface (meters)
    'dirt_radius': 0.22,          # Radius of dirt surface (meters)
    'dirt_segments': 16,          # Detail of dirt surface
    
    # Dirt material
    'dirt_color': (0.18, 0.12, 0.08, 1.0),  # Rich dark brown
    'dirt_roughness': 0.95,
}

# ============================================================================
# GENERATOR FUNCTIONS
# ============================================================================

def append_component(filepath, object_name):
    """Append a component from the library."""
    if not Path(filepath).exists():
        print(f"  ✗ Component not found: {filepath}")
        return None
    
    with bpy.data.libraries.load(filepath) as (data_from, data_to):
        data_to.objects = [name for name in data_from.objects if name == object_name]
    
    obj = None
    for loaded_obj in data_to.objects:
        if loaded_obj:
            bpy.context.collection.objects.link(loaded_obj)
            obj = loaded_obj
            print(f"  ✓ Appended: {object_name} from {Path(filepath).name}")
    
    return obj

def create_dirt_surface(config):
    """Create the dirt surface geometry."""
    mesh = bpy.data.meshes.new("DirtMesh")
    bm = bmesh.new()
    
    dirt_z = config['dirt_z']
    dirt_radius = config['dirt_radius']
    segments = config['dirt_segments']
    
    # Create center vertex
    center = bm.verts.new((0, 0, dirt_z))
    
    # Create outer ring
    outer_verts = []
    for i in range(segments):
        angle = (2 * math.pi * i) / segments
        x = dirt_radius * math.cos(angle)
        y = dirt_radius * math.sin(angle)
        vert = bm.verts.new((x, y, dirt_z))
        outer_verts.append(vert)
    
    # Create triangular faces (center to each pair of outer vertices)
    for i in range(segments):
        v1 = outer_verts[i]
        v2 = outer_verts[(i + 1) % segments]
        bm.faces.new([center, v1, v2])
    
    # Smooth shading
    for face in bm.faces:
        face.smooth = True
    
    bm.to_mesh(mesh)
    bm.free()
    
    return mesh

def create_dirt_material(config):
    """Create the dirt material."""
    mat = bpy.data.materials.new(name="DirtMaterial")
    mat.use_nodes = True
    
    nodes = mat.node_tree.nodes
    nodes.clear()
    
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = config['dirt_color']
    bsdf.inputs['Roughness'].default_value = config['dirt_roughness']
    bsdf.inputs['Metallic'].default_value = 0.0
    
    output = nodes.new(type='ShaderNodeOutputMaterial')
    mat.node_tree.links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    
    return mat

def compose_potted_plant(config=COMPOSITION_CONFIG, output_path=None):
    """
    Compose a potted plant from components.
    
    Args:
        config: Configuration dictionary
        output_path: Optional path to save .blend file
    
    Returns:
        The composed potted plant object
    """
    print(f"\n=== COMPOSING POTTED PLANT ===")
    
    # Clear scene
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    
    # Determine library path
    script_dir = Path(__file__).parent.parent.parent  # Go up to project root
    library_dir = script_dir / "assets" / "models" / "library"
    
    # Append pot
    print("\nLoading components...")
    pot_path = str(library_dir / config['pot_file'])
    pot = append_component(pot_path, "Pot")
    
    if not pot:
        print("  ✗ Failed to load pot")
        return None
    
    # Append foliage
    foliage_path = str(library_dir / config['foliage_file'])
    foliage = append_component(foliage_path, "Foliage")
    
    if not foliage:
        print("  ✗ Failed to load foliage")
        return None
    
    # Position foliage
    foliage.location = (0, 0, config['foliage_z_offset'])
    foliage.scale = (config['foliage_scale'], config['foliage_scale'], config['foliage_scale'])
    print(f"  ✓ Positioned foliage at Z={config['foliage_z_offset']}")
    
    # Create dirt surface
    print("\nCreating dirt surface...")
    dirt_mesh = create_dirt_surface(config)
    dirt_obj = bpy.data.objects.new("Dirt", dirt_mesh)
    bpy.context.collection.objects.link(dirt_obj)
    
    # Apply dirt material
    dirt_mat = create_dirt_material(config)
    dirt_obj.data.materials.append(dirt_mat)
    print(f"  ✓ Created dirt surface")
    
    # Join all components into single object
    print("\nJoining components...")
    bpy.context.view_layer.objects.active = pot
    pot.select_set(True)
    foliage.select_set(True)
    dirt_obj.select_set(True)
    
    bpy.ops.object.join()
    
    potted_plant = bpy.context.active_object
    potted_plant.name = "PottedPlant"
    potted_plant.location = (0, 0, 0)
    
    # Calculate stats
    poly_count = len(potted_plant.data.polygons)
    material_count = len(potted_plant.data.materials)
    print(f"\n📊 COMPOSITION STATS:")
    print(f"  Total polygons: {poly_count}")
    print(f"  Materials: {material_count}")
    print(f"  Components: Pot + Foliage + Dirt")
    
    # Save if path provided
    if output_path:
        bpy.ops.wm.save_as_mainfile(filepath=output_path)
        print(f"\n✅ Saved: {output_path}")
    
    return potted_plant

def main():
    """Main function for standalone execution."""
    # Determine output path
    script_dir = Path(__file__).parent.parent.parent  # Go up to project root
    output_path = str(script_dir / "assets" / "models" / "library" / "PottedPlant.blend")
    
    # Compose potted plant
    compose_potted_plant(COMPOSITION_CONFIG, output_path)
    
    print(f"\n✅ Potted plant composition complete\n")

if __name__ == "__main__":
    main()

