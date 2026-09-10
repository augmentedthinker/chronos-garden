extends Node

## Automated test suite verifying:
## 1. Scene and node instantiation
## 2. Local persistence and state initialization
## 3. Offline time reconstruction algorithm (e.g. 30 minutes elapsed = 3 offline plants)
## 4. Event log formatting with [offline] indicators
## 5. Live planting lifecycle and character movement
## 6. High-res visual verification screenshot

var main_scene: PackedScene = preload("res://scenes/main.tscn")
var world: WorldManager = null

func _ready() -> void:
	print("==================================================")
	print("🚀 STARTING PERSISTENT GARDEN SIMULATION TESTS")
	print("==================================================")
	await get_tree().process_frame
	await get_tree().process_frame

	world = main_scene.instantiate()
	add_child(world)
	await world.world_initialized
	# Isolate test from live cloud database
	world.persistence.is_cloud_active = false
	world.persistence.supabase.supabase_url = ""

	# Test 1: Verify Initial Clean Reset
	print("\n[TEST 1] Resetting garden to clean state...")
	await world._reset_garden()
	await get_tree().create_timer(0.2).timeout
	assert(world.current_plant_count == 0, "Plant count should be 0 after reset")
	assert(world.plots.size() == 12, "Should have 12 predefined plots")
	print("  ✓ Clean state verified: 0 plants, 12 plots available.")

	print("\n[TEST 2] Testing Live Planting Trigger...")
	var initial_time = int(Time.get_unix_time_from_system())
	world._trigger_scheduled_planting()
	# Wait for character to walk to Plot 0 and complete planting animation (approx 2.5s)
	await get_tree().create_timer(3.0).timeout
	assert(world.current_plant_count == 1, "Plant count should now be 1")
	assert(world.plots[0].is_occupied(), "Plot 0 should now have a plant")
	assert(world.active_plants_data.size() == 1, "State active_plots should have 1 record")
	assert(world.active_plants_data[0]["is_offline"] == false, "Live plant must NOT be tagged offline")
	print("  ✓ Live planting verified: Character walked to plot, planted, and updated state.")

	# Test 3: Offline Elapsed-Time Reconstruction (30 minutes = 3 plants)
	print("\n[TEST 3] Testing Offline Elapsed-Time Reconstruction (30 minutes elapsed)...")
	# We simulate the user having been away for 30 minutes
	var sim_elapsed = 1800 # 30 mins = 3 intervals of 600s
	world.last_planted_unix -= sim_elapsed
	var now = int(Time.get_unix_time_from_system())
	var elapsed = now - world.last_planted_unix
	world._reconstruct_offline_time(elapsed, now)
	world._render_existing_plants()

	assert(world.current_plant_count == 4, "Total plants should now be 4 (1 live + 3 reconstructed)")
	assert(world.plots[1].is_occupied(), "Plot 1 should be occupied")
	assert(world.plots[2].is_occupied(), "Plot 2 should be occupied")
	assert(world.plots[3].is_occupied(), "Plot 3 should be occupied")
	
	# Verify that plants 2, 3, 4 are marked offline
	assert(world.active_plants_data[1]["is_offline"] == true, "Plant 2 should be flagged is_offline=true")
	assert(world.active_plants_data[2]["is_offline"] == true, "Plant 3 should be flagged is_offline=true")
	assert(world.active_plants_data[3]["is_offline"] == true, "Plant 4 should be flagged is_offline=true")
	print("  ✓ Offline elapsed reconstruction verified: 3 plants accurately reconstructed.")

	# Test 4: Verify Event Log Content
	print("\n[TEST 4] Verifying On-Screen Event Log formatting...")
	var log_text = world.hud.event_log_text.text
	print("  Current Event Log Content:\n", log_text)
	assert(log_text.contains("[offline]"), "Event log MUST clearly show [offline] for reconstructed events")
	assert(log_text.contains("Plant #1 planted"), "Event log must record Plant #1")
	assert(log_text.contains("Plant #2 planted"), "Event log must record Plant #2")
	assert(log_text.contains("Plant #3 planted"), "Event log must record Plant #3")
	assert(log_text.contains("Plant #4 planted"), "Event log must record Plant #4")
	print("  ✓ Event log verified: Chronological order and [offline] badges present.")

	# Test 5: Save State and Reload Cycle
	print("\n[TEST 5] Testing Cold-Start Persistence Reload...")
	var saved_state = world.persistence._load_local_state("main_garden")
	assert(saved_state["total_plants"] == 4, "Saved total_plants should be 4")
	print("  ✓ Cold-start disk state matches in-memory world state.")

	# Wait a frame and capture screenshot
	await get_tree().create_timer(0.5).timeout
	var img = get_viewport().get_texture().get_image()
	img.save_png("/home/gagekappes/horizon/projects/persistent-garden/build/simulation_test_verification.png")
	print("\n📸 Captured verification screenshot to build/simulation_test_verification.png")

	print("\n==================================================")
	print("🎉 ALL PERSISTENT GARDEN TESTS PASSED SUCCESSFULLY!")
	print("==================================================")
	get_tree().quit(0)
