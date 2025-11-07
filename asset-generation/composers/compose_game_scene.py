"""
Blender script to compose GameScene from library assets.

Usage:
    blender --background --python compose_game_scene.py
    
Or run from Blender's Scripting workspace.
"""

import bpy
import os
from pathlib import Path

def clear_scene():
    """Remove all objects from the current scene."""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    print("✓ Cleared scene")

def get_asset_path(asset_name):
    """Get full path to a library asset."""
    script_dir = Path(__file__).parent.parent.parent  # Go up to project root
    library_dir = script_dir / "assets" / "models" / "library"
    return str(library_dir / f"{asset_name}.blend")

def append_asset(asset_file, object_name):
    """Append an asset from the library."""
    asset_path = get_asset_path(asset_file)
    
    if not Path(asset_path).exists():
        print(f"✗ Asset not found: {asset_path}")
        return None
    
    with bpy.data.libraries.load(asset_path) as (data_from, data_to):
        data_to.objects = [name for name in data_from.objects if name == object_name]
    
    appended_obj = None
    for obj in data_to.objects:
        if obj:
            bpy.context.collection.objects.link(obj)
            appended_obj = obj
            print(f"  ✓ Appended: {object_name} from {asset_file}.blend")
    
    return appended_obj

def create_instance(source_obj, name, location, rotation=(0,0,0)):
    """Create an instance of an object (shares mesh data)."""
    instance = source_obj.copy()
    instance.data = source_obj.data  # Share mesh data
    instance.name = name
    instance.location = location
    instance.rotation_euler = rotation
    bpy.context.collection.objects.link(instance)
    print(f"  ✓ Created instance: {name} at {location}")
    return instance

def compose_scene():
    """Compose the game scene from library assets."""
    print("\n=== COMPOSING GAME SCENE ===\n")
    
    # Clear existing scene
    clear_scene()
    
    # Add ground plane
    print("Adding ground plane...")
    ground = append_asset("GroundPlane", "GroundPlane")
    
    # Add backdrop (three separate objects: top panel, left panel, right panel)
    print("\nAdding backdrop...")
    top_panel = append_asset("Backdrop", "TopPanel")
    left_panel = append_asset("Backdrop", "BackdropLeft")
    right_panel = append_asset("Backdrop", "BackdropRight")
    
    if top_panel and left_panel and right_panel:
        # Position all panels BEHIND the character and plants (away from camera)
        # Blender: (X, Y, Z) where Z is up, Y is forward/back
        # Thermion: (X, Y, Z) where Y is up, Z is forward/back
        # Camera is at Z=3.0 looking at character at (0,0,0)
        # Plants are at Y=2.5 in Blender (forward from character)
        # To be BEHIND plants, backdrop needs Y > 2.5 in Blender
        # Positive Y in Blender = negative Z in Thermion (behind character) ✓
        backdrop_y = 3.5  # Further back than plants (Y=2.5)
        
        # Top panel: full width, resting on top of side panels (same Y depth)
        top_panel.location = (0, backdrop_y, top_panel.location.z)  # Same Y depth as side panels
        print(f"  ✓ Positioned top panel at {top_panel.location} (resting on side panels)")
        
        # Left panel: left side, below top panel
        left_panel.location = (left_panel.location.x, backdrop_y, left_panel.location.z)
        print(f"  ✓ Positioned left panel at {left_panel.location}")
        
        # Right panel: right side, below top panel
        right_panel.location = (right_panel.location.x, backdrop_y, right_panel.location.z)
        print(f"  ✓ Positioned right panel at {right_panel.location} (opening in center)")
    
    # Add fusuma panels (foreground framing)
    print("\nAdding fusuma panels...")
    fusuma_left = append_asset("Fusuma", "Fusuma")
    if fusuma_left:
        # Position left fusuma - camera looks past it into the room
        # Fusuma should be MUCH closer to camera and closer together (5 units apart total)
        fusuma_left.location = (-2.5, -2.0, 0)  # Left side, very close to camera
        fusuma_left.rotation_euler = (0, 0, 0)  # No tilt - straight
        print(f"  ✓ Positioned left fusuma at {fusuma_left.location}")
    
    fusuma_right = append_asset("Fusuma", "Fusuma")
    if fusuma_right:
        # Position right fusuma - 5 units apart from left (so 2.5 units from center each)
        fusuma_right.location = (2.5, -2.0, 0)  # Right side, very close to camera
        fusuma_right.rotation_euler = (0, 0, 0)  # No tilt - straight
        print(f"  ✓ Positioned right fusuma at {fusuma_right.location} (5 units apart)")
    
    # Note: Rug is now loaded separately in Flutter with personalized texture
    # (Removed from GameScene to allow dynamic texture application)
    
    # Note: Books removed - didn't fit the aesthetic (preserved in library for future refinement)
    
    # Add first plant
    print("\nAdding plants...")
    plant1 = append_asset("PottedPlant", "PottedPlant")
    
    if plant1:
        # Position first plant
        plant1.location = (-1.0, 2.5, -0.1)
        print(f"  ✓ Positioned plant1 at {plant1.location}")
        
        # Create second plant as instance
        plant2 = create_instance(
            plant1, 
            "PottedPlant_Instance2",
            location=(1.0, 2.5, -0.1),
            rotation=(0, 0, 0.5)  # Slight rotation for variety
        )
    
    # Calculate stats
    total_objects = len([obj for obj in bpy.data.objects if obj.type == 'MESH'])
    total_meshes = len(bpy.data.meshes)
    total_polys = sum(len(obj.data.polygons) for obj in bpy.data.objects if obj.type == 'MESH' and obj.data)
    
    print(f"\n📊 SCENE STATS:")
    print(f"  Objects: {total_objects}")
    print(f"  Mesh data blocks: {total_meshes} (instances share geometry)")
    print(f"  Total polygons: {total_polys}")
    
    return True

def save_scene():
    """Save the composed scene."""
    script_dir = Path(__file__).parent.parent.parent  # Go up to project root
    scenes_dir = script_dir / "assets" / "models" / "scenes"
    scenes_dir.mkdir(exist_ok=True)
    
    scene_path = str(scenes_dir / "GameScene.blend")
    bpy.ops.wm.save_as_mainfile(filepath=scene_path)
    print(f"\n✅ Saved scene: {scene_path}")

def export_glb():
    """Export the scene as GLB."""
    script_dir = Path(__file__).parent.parent.parent  # Go up to project root
    exports_dir = script_dir / "assets" / "models" / "exports"
    exports_dir.mkdir(exist_ok=True)
    
    glb_path = str(exports_dir / "GameScene.glb")
    
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format='GLB',
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        use_selection=False,
        export_cameras=False,
        export_lights=False
    )
    
    print(f"✅ Exported GLB: {glb_path}")
    
    # Also export to legacy location for backward compatibility
    legacy_path = str(script_dir / "assets" / "models" / "GroundPlane.glb")
    bpy.ops.export_scene.gltf(
        filepath=legacy_path,
        export_format='GLB',
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        use_selection=False,
        export_cameras=False,
        export_lights=False
    )
    print(f"✅ Exported GLB (legacy): {legacy_path}")

def main():
    """Main function."""
    print("\n" + "="*60)
    print("  GAME SCENE COMPOSER")
    print("="*60)
    
    # Compose scene from library assets
    if compose_scene():
        # Save the blend file
        save_scene()
        
        # Export as GLB
        export_glb()
        
        print("\n" + "="*60)
        print("  ✅ SCENE COMPOSITION COMPLETE")
        print("="*60 + "\n")
    else:
        print("\n✗ Scene composition failed")

if __name__ == "__main__":
    main()

