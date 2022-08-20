const std = @import("std");

/// Associative array. Like a hashmap but with much worse performance, but it is a lot less complex
pub fn Assoc(comptime T: type) type {
    return struct {
        key: usize,
        val: T,

        /// Returns index of item
        pub fn get(items: []@This(), key: usize) ?usize {
            for (items) |item, i| {
                if (item.key == key) {
                    return i;
                }
            }
            return null;
        }

        pub fn swapRemove(items: []@This(), to_remove: usize, to_swap: usize) []@This() {
            var new_items = items;
            for (items) |item, i| {
                if (item.key == to_remove) {
                    if (i != items.len - 1) {
                        std.mem.swap(@This(), &items[i], &items[items.len - 1]);
                    }
                    new_items = items[0 .. items.len - 1];
                    break;
                }
            }
            for (items) |item, i| {
                if (item.key == to_swap) {
                    items[i].key = to_remove;
                }
            }
            return new_items;
        }
    };
}
