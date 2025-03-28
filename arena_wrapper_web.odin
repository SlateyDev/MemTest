#+build wasm32, wasm64p32

package app

import "core:mem"

WrappedArena :: mem.Dynamic_Arena

wrapped_arena_destroy :: proc(arena: ^mem.Dynamic_Arena) {
    mem.dynamic_arena_destroy(arena)
    arena.alignment = 0
}

wrapped_arena_reset :: proc(arena: ^mem.Dynamic_Arena, loc := #caller_location) {
    mem.dynamic_arena_reset(arena, loc)
}

wrapped_arena_free_all :: proc(arena: ^mem.Dynamic_Arena, loc := #caller_location) {
    mem.dynamic_arena_free_all(arena, loc)
}

wrapped_arena_is_configured :: proc(arena: ^mem.Dynamic_Arena) -> bool {
    return arena.alignment != 0
}

wrapped_arena_init :: proc(arena: ^mem.Dynamic_Arena) -> (err: mem.Allocator_Error) {
    mem.dynamic_arena_init(arena)
    return
}

wrapped_arena_allocator :: proc(arena: ^mem.Dynamic_Arena) -> mem.Allocator {
    return mem.dynamic_arena_allocator(arena)
}