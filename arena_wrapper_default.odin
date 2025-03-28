#+build !wasm32
#+build !wasm64p32

package app

import "core:mem"
import vmem "core:mem/virtual"

WrappedArena :: vmem.Arena

destroy_arena :: proc(arena: ^vmem.Arena, loc := #caller_location) {
    vmem.arena_destroy(arena, loc)
    arena.total_reserved = 0
}

reset_arena :: proc(arena: ^vmem.Arena, loc := #caller_location) {
    vmem.arena_free_all(arena, loc)
}

arena_free_all :: proc(arena: ^vmem.Arena, loc := #caller_location) {
    vmem.arena_free_all(arena, loc)
}

arena_is_configured :: proc(arena: ^vmem.Arena) -> bool {
    return arena.total_reserved != 0
}

arena_init :: proc(arena: ^vmem.Arena) -> (err: mem.Allocator_Error) {
    err = vmem.arena_init_growing(arena)
    return
}

arena_allocator :: proc(arena: ^vmem.Arena) -> mem.Allocator {
    return vmem.arena_allocator(arena)
}