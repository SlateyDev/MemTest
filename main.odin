package app

import "core:c/libc"
import "core:fmt"
import "core:mem"
import ha "handle_array"

main :: proc() {
	when ODIN_DEBUG {
		//Setup tracking allocator to test for memory leaks
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	} else {
		_ :: mem
	}

	fmt.println("TESTING")
    _ = libc.getchar()

    run_mem_test()

    fmt.println("COMPLETED")
    _ = libc.getchar()
}

My_Struct_Handle :: distinct ha.Handle
My_Struct :: struct {
    handle: My_Struct_Handle,
    position: [3]f32,
    rotation: quaternion128,
    scale: [3]f32,
}
my_data: ha.Array(My_Struct, My_Struct_Handle)

run_mem_test :: proc() {
    h1 := ha.array_add(&my_data, My_Struct {position = {10, 10, 10}, rotation = 0, scale = {1, 1, 1}})
    h2 := ha.array_add(&my_data, My_Struct {position = {11, 11, 11}, rotation = 0, scale = {1, 1, 1}})
    h3 := ha.array_add(&my_data, My_Struct {position = {12, 12, 12}, rotation = 0, scale = {1, 1, 1}})

    ha.array_remove(&my_data, h2)

    h4 := ha.array_add(&my_data, My_Struct {position = {20, 20, 20}, rotation = 10, scale = {2, 2, 2}})

    assert(h4.idx == 4)

    assert(h1.idx == 1)
	assert(h2.idx == 2)
	assert(h3.idx == 3)
	assert(h1.gen == 1)
	assert(h2.gen == 1)
	assert(h3.gen == 1)

	if _, ok := ha.array_get(my_data, h2); ok {
		panic("h2 should not be valid")
	}

	if h4_ptr := ha.array_get_ptr(my_data, h4); h4_ptr != nil {
		assert(h4_ptr.position == {20, 20, 20})
		h4_ptr.position = {30, 30, 30}
	} else {
		panic("h4 should be valid")
	}

	if h4_val, ok := ha.array_get(my_data, h4); ok {
		assert(h4_val.position == {30, 30, 30})
	} else {
		panic("h4 should be valid")
	}

	// This call moves new items from new_items into items. Needs to be run for example at
	// end of frame in a game.
	ha.array_commit_new(&my_data)

	if h4_val, ok := ha.array_get(my_data, h4); ok {
		assert(h4_val.position == {30, 30, 30})
	} else {
		panic("h4 should be valid")
	}

	ha.array_remove(&my_data, h4)
	h5 := ha.array_add(&my_data, My_Struct {position = {60, 60, 60}})
	assert(h5.idx == 4)

    for _ in 0..<100 {
        for _ in 0..<1000 {
            _ = ha.array_add(&my_data, My_Struct {position = {5,5,5}})
        }
        ha.array_commit_new(&my_data)
    }

	fmt.println("Allocation completed")
    _ = libc.getchar()

	ha.array_delete(&my_data)

	fmt.println("Delete completed")
    _ = libc.getchar()

	h10 := ha.array_add(&my_data, My_Struct {position = {10, 10, 10}, rotation = 0, scale = {1, 1, 1}})
    assert(h10.idx == 1)
	ha.array_delete(&my_data)
}