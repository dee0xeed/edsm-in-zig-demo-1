
pub fn opaqPtrTo(ptr: ?*anyopaque, comptime T: type) T {
    //return @ptrCast(T, @alignCast(@alignOf(T), ptr));
    return @ptrCast(@alignCast(ptr));
}
