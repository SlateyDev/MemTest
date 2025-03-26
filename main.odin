package app

import "core:c/libc"
import "core:fmt"
import "core:mem"
// import "core:time"

main :: proc() {
    fmt.println("TESTING")

    run_mem_test()

    fmt.println("COMPLETED")
    _ = libc.getchar()
}

My_Struct :: struct {
    handle: My_Struct_Handle,
    position: [3]f32,
    rotation: quaternion128,
    scale: [3]f32,
}
My_Struct_Handle :: distinct Handle
ha: Handle_Array(My_Struct, My_Struct_Handle)

run_mem_test :: proc() {
    h1 := ha_add(&ha, My_Struct {position = {10, 10, 10}, rotation = 0, scale = {1, 1, 1}})
    h2 := ha_add(&ha, My_Struct {position = {11, 11, 11}, rotation = 0, scale = {1, 1, 1}})
    h3 := ha_add(&ha, My_Struct {position = {12, 12, 12}, rotation = 0, scale = {1, 1, 1}})

    ha_remove(&ha, h2)

    h4 := ha_add(&ha, My_Struct {position = {20, 20, 20}, rotation = 10, scale = {2, 2, 2}})

    assert(h4.idx == 4)

    assert(h1.idx == 1)
	assert(h2.idx == 2)
	assert(h3.idx == 3)
	assert(h1.gen == 1)
	assert(h2.gen == 1)
	assert(h3.gen == 1)

	if _, ok := ha_get(ha, h2); ok {
		panic("h2 should not be valid")
	}

	if h4_ptr := ha_get_ptr(ha, h4); h4_ptr != nil {
		assert(h4_ptr.position == {20, 20, 20})
		h4_ptr.position = {30, 30, 30}
	} else {
		panic("h4 should be valid")
	}

	if h4_val, ok := ha_get(ha, h4); ok {
		assert(h4_val.position == {30, 30, 30})
	} else {
		panic("h4 should be valid")
	}

	// This call moves new items from new_items into items. Needs to be run for example at
	// end of frame in a game.
	ha_commit_new(&ha)

	if h4_val, ok := ha_get(ha, h4); ok {
		assert(h4_val.position == {30, 30, 30})
	} else {
		panic("h4 should be valid")
	}

	ha_remove(&ha, h4)
	h5 := ha_add(&ha, My_Struct {position = {60, 60, 60}})
	assert(h5.idx == 4)

	ha_delete(ha)

    for _ in 0..<100 {
        for _ in 0..<1000 {
            _ = ha_add(&ha, My_Struct {position = {5,5,5}})
        }
        ha_commit_new(&ha)
    }

    _ = libc.getchar()

    mem.dynamic_arena_destroy(&ha.new_items_arena)
    delete(ha.items)
}