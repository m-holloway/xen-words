"""
Rebuild All Assets

Runs all procedural generators to rebuild the asset library from scratch.
This is useful when you want to update all assets with new parameters.

Usage:
    blender --background --python rebuild_all.py
"""

import bpy
import sys
from pathlib import Path

# Add generators to path
script_dir = Path(__file__).parent.parent  # asset-generation/
generators_dir = script_dir / "generators"
sys.path.insert(0, str(generators_dir))

# Import generators
from generate_pot import generate_pot, POT_CONFIG
from generate_foliage import generate_foliage, FOLIAGE_CONFIG
from generate_potted_plant import compose_potted_plant, COMPOSITION_CONFIG

def rebuild_all():
    """Rebuild all assets from generators."""
    print("\n" + "="*70)
    print("  REBUILDING ALL ASSETS")
    print("="*70)
    
    project_root = script_dir.parent  # Up to project root
    assets_dir = project_root / "assets" / "models" / "library"
    assets_dir.mkdir(exist_ok=True)
    
    # 1. Generate Pot
    print("\n[1/3] Generating Pot...")
    pot_path = str(assets_dir / "Pot.blend")
    try:
        generate_pot(POT_CONFIG, pot_path)
        print("  ✅ Pot generated successfully")
    except Exception as e:
        print(f"  ✗ Pot generation failed: {e}")
        return False
    
    # 2. Generate Foliage
    print("\n[2/3] Generating Foliage...")
    foliage_path = str(assets_dir / "Foliage.blend")
    try:
        generate_foliage(FOLIAGE_CONFIG, foliage_path)
        print("  ✅ Foliage generated successfully")
    except Exception as e:
        print(f"  ✗ Foliage generation failed: {e}")
        return False
    
    # 3. Compose PottedPlant
    print("\n[3/3] Composing PottedPlant...")
    plant_path = str(assets_dir / "PottedPlant.blend")
    try:
        compose_potted_plant(COMPOSITION_CONFIG, plant_path)
        print("  ✅ PottedPlant composed successfully")
    except Exception as e:
        print(f"  ✗ PottedPlant composition failed: {e}")
        return False
    
    # Now rebuild game scene
    print("\n[Bonus] Rebuilding GameScene...")
    compose_scene_script = script_dir / "composers" / "compose_game_scene.py"
    if compose_scene_script.exists():
        try:
            # Import and run
            sys.path.insert(0, str(script_dir / "composers"))
            from compose_game_scene import main as compose_main
            compose_main()
            print("  ✅ GameScene rebuilt successfully")
        except Exception as e:
            print(f"  ⚠ GameScene rebuild failed: {e}")
    
    print("\n" + "="*70)
    print("  ✅ ALL ASSETS REBUILT SUCCESSFULLY")
    print("="*70 + "\n")
    
    return True

def main():
    """Main function."""
    success = rebuild_all()
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()

