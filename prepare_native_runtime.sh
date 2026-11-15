#!/bin/zsh
# Prepare ignored native runtime data for both localhost and LAN hosting.
set -euo pipefail
project_dir="${0:A:h}"
python3 "$project_dir/extract_client_catalog.py"
python3 "$project_dir/prepare_native_weapons.py"
python3 "$project_dir/prepare_native_audio.py"
node "$project_dir/prepare_native_contact_audio.js"
python3 "$project_dir/prepare_native_environment.py"
python3 "$project_dir/prepare_native_atmosphere.py"
python3 "$project_dir/prepare_native_water_waves.py"
python3 "$project_dir/prepare_native_camera.py"
python3 "$project_dir/prepare_native_effects.py"
node "$project_dir/prepare_native_particle_effects.js"
node "$project_dir/prepare_native_physics.js"
node "$project_dir/prepare_native_vehicle_rigs.js" --all --if-needed
python3 "$project_dir/prepare_native_riders.py"
node "$project_dir/prepare_native_foot_animation.js"
node "$project_dir/prepare_native_flight_assets.js" --archive-missing
node "$project_dir/prepare_native_radio.js"
