package app

import "core:testing"
import "core:fmt"
import "core:mem"

_ :: fmt

Handle :: struct {
	idx: u32,
	gen: u32,
}

HANDLE_NONE :: Handle {}

Handle_Array :: struct($T: typeid, $HT: typeid) {
	items: [dynamic]T,
	unused_items: [dynamic]u32,
	allocator: mem.Allocator,

	// To make sure we do not invalidate `items` in the middle of a frame, while there are pointers
	// to things it, we add new items to this, and the new items are allocated using the growing
	// virtual arena `new_items_arena`. Run `ha_commit_new` once in a while to move things from
	new_items: [dynamic]^T,
	new_items_arena: mem.Dynamic_Arena,
}

ha_delete :: proc(handle_array: ^Handle_Array($T, $HT), loc := #caller_location) {
	delete(handle_array.items, loc)
	delete(handle_array.unused_items, loc)
	delete(handle_array.new_items)
	mem.dynamic_arena_destroy(&handle_array.new_items_arena)

	//Clear these out so the memory spaces are recreated if there is an attempt to add items again
	handle_array.items = nil
	handle_array.unused_items = nil
	handle_array.new_items = nil
	handle_array.new_items_arena.alignment = 0
}

ha_clear :: proc(handle_array: ^Handle_Array($T, $HT), loc := #caller_location) {
	clear(&handle_array.items)
	clear(&handle_array.unused_items)
	clear(&handle_array.new_items)
	mem.dynamic_arena_reset(&handle_array.new_items_arena)
}

// Call this at a safe space when there are no pointers in flight. It will move things from
// new_items into items, potentially making it grow. Those new items live on a growing virtual
// memory arena until this is called.
ha_commit_new :: proc(handle_array: ^Handle_Array($T, $HT), loc := #caller_location) {
	if len(handle_array.items) == 0 {
		// Dummy item at idx zero
		append(&handle_array.items, T{})
	}

	for new_item in handle_array.new_items {
		if new_item == nil {
			// We must add these, if we don't the indices get out of order with regards to handles
			// we have handed out. We'll just add them as empty objects and then put the index into
			// unused items.
			unused_item_idx := len(handle_array.items)
			append(&handle_array.items, T {
                handle = {
                    gen = 1,
                },
			})

			append(&handle_array.unused_items, u32(unused_item_idx))
			continue
		}

		append(&handle_array.items, new_item^)
	}

	mem.dynamic_arena_free_all(&ha.new_items_arena)
	handle_array.new_items = {}
}

ha_clone :: proc(handle_array: Handle_Array($T, $HT), allocator := context.allocator, loc := #caller_location) -> Handle_Array(T, HT) {
	return Handle_Array(T, HT) {
		items = slice.clone_to_dynamic(handle_array.items[:], allocator, loc),
		unused_items = slice.clone_to_dynamic(handle_array.unused_items[:], allocator, loc),
		allocator = allocator,
	}
}

ha_add :: proc(handle_array: ^Handle_Array($T, $HT), value: T, loc := #caller_location) -> HT {
	if handle_array.items == nil {
		if handle_array.allocator == {} {
			handle_array.allocator = context.allocator
		}

		handle_array.items = make([dynamic]T, handle_array.allocator, loc)
		handle_array.unused_items = make([dynamic]u32, handle_array.allocator, loc)
	}

	value := value

	if len(handle_array.unused_items) > 0 {
		reuse_idx := pop(&handle_array.unused_items)
		reused := &handle_array.items[reuse_idx]
		handle := reused.handle
		reused^ = value
		reused.handle.idx = u32(reuse_idx)
		reused.handle.gen = handle.gen + 1
		return reused.handle
	}

	if len(handle_array.items) == 0 {
		// Dummy item at idx zero
		append(&handle_array.items, T{})
	}

    if handle_array.new_items_arena.alignment == 0 {
        mem.dynamic_arena_init(&handle_array.new_items_arena)
    }

	new_items_allocator := mem.dynamic_arena_allocator(&handle_array.new_items_arena)
	new_item := new(T, new_items_allocator)
	new_item^ = value
	new_item.handle.idx = u32(len(handle_array.items) + len(handle_array.new_items))
	new_item.handle.gen = 1

	if handle_array.new_items == nil {
		handle_array.new_items = make([dynamic]^T, new_items_allocator)
	}

	append(&handle_array.new_items, new_item)
	return new_item.handle
}

ha_get :: proc(handle_array: Handle_Array($T, $HT), handle: HT) -> (T, bool) #optional_ok {
	if ptr := ha_get_ptr(handle_array, handle); ptr != nil {
		return ptr^, true
	}

	return {}, false
}

ha_get_ptr :: proc(handle_array: Handle_Array($T, $HT), handle: HT) -> ^T {
	if handle.idx == 0 || handle.idx < 0 {
		return nil
	}

	if int(handle.idx) >= len(handle_array.items) {
		// The item we look for might be in `new_items`, so look in there too
		new_idx := handle.idx - u32(len(handle_array.items))
		
		if new_idx >= u32(len(handle_array.new_items)) {
			return nil
		}

		if item := handle_array.new_items[new_idx]; item != nil && item.handle == handle {
			return item
		}

		return nil
	}

	if item := &handle_array.items[handle.idx]; item.handle == handle {
		return item
	}

	return nil
}

ha_remove :: proc(handle_array: ^Handle_Array($T, $HT), handle: HT) {
	if handle.idx == 0 || handle.idx < 0 {
		return
	}

	if int(handle.idx) >= len(handle_array.items) {
		new_idx := handle.idx - u32(len(handle_array.items))
		
		if new_idx < u32(len(handle_array.new_items)) {
			// This stops this item from being added during `ha_commit_new`
			handle_array.new_items[new_idx] = nil
		}

		return
	}

	if item := &handle_array.items[handle.idx]; item.handle == handle {
		append(&handle_array.unused_items, handle.idx)

		// This makes the item invalid. We'll set the index back if the slot is reused.
		item.handle.idx = 0
	}
}

ha_valid :: proc(handle_array: Handle_Array($T, $HT), handle: HT) -> bool {
	return ha_get_ptr(handle_array, handle) != nil
}

Handle_Array_Iter :: struct($T: typeid, $HT: typeid) {
	handle_array: ^Handle_Array(T, HT),
	index: int,
}

ha_make_iter :: proc(handle_array: ^Handle_Array($T, $HT)) -> Handle_Array_Iter(T, HT) {
	return { handle_array = handle_array }
}

ha_iter :: proc(it: ^Handle_Array_Iter($T, $HT)) -> (val: T, handle: HT, cond: bool) {
	val_ptr: ^T

	val_ptr, handle, cond = ha_iter_ptr(it)

	if val_ptr != nil {
		val = val_ptr^
	}

	return
}

ha_iter_ptr :: proc(it: ^Handle_Array_Iter($T, $HT)) -> (val: ^T, handle: HT, cond: bool) {
	cond = it.index < len(it.handle_array.items) + len(it.handle_array.new_items)

	for ; cond; cond = it.index < len(it.handle_array.items) + len(it.handle_array.new_items) {
		// Handle items in new_items
		if it.index >= len(it.handle_array.items) {
			idx := it.index - len(it.handle_array.items)

			if it.handle_array.new_items[idx] == nil {
				it.index += 1
				continue
			}

			val = it.handle_array.new_items[idx]
			handle = val.handle
			it.index += 1
			break
		}

		if it.handle_array.items[it.index].handle.idx == 0 {
			it.index += 1
			continue
		}

		val = &it.handle_array.items[it.index]
		handle = val.handle
		it.index += 1
		break
	}

	return
}

// Test handle array and basic usage documentation.
@(test)
ha_test :: proc(t: ^testing.T) {
	Ha_Test_Entity :: struct {
		handle: Ha_Test_Entity_Handle,
		pos: [2]f32,
		vel: [2]f32,
	}

	Ha_Test_Entity_Handle :: distinct Handle

	ha: Handle_Array(Ha_Test_Entity, Ha_Test_Entity_Handle)

	h1 := ha_add(&ha, Ha_Test_Entity {pos = {1, 2}})
	h2 := ha_add(&ha, Ha_Test_Entity {pos = {2, 2}})
	h3 := ha_add(&ha, Ha_Test_Entity {pos = {3, 2}})

	ha_remove(&ha, h2)

	// This one will reuse the slot h2 had
	h4 := ha_add(&ha, Ha_Test_Entity {pos = {4, 2}})
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
		assert(h4_ptr.pos == {4, 2})
		h4_ptr.pos = {5, 2}
	} else {
		panic("h4 should be valid")
	}

	if h4_val, ok := ha_get(ha, h4); ok {
		assert(h4_val.pos == {5, 2})
	} else {
		panic("h4 should be valid")
	}

	// This call moves new items from new_items into items. Needs to be run for example at
	// end of frame in a game.
	ha_commit_new(&ha)

	if h4_val, ok := ha_get(ha, h4); ok {
		assert(h4_val.pos == {5, 2})
	} else {
		panic("h4 should be valid")
	}

	ha_remove(&ha, h4)
	h5 := ha_add(&ha, Ha_Test_Entity {pos = {6, 2}})
	assert(h5.idx == 4)

	ha_delete(&ha)
}