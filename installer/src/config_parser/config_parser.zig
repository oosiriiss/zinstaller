const std = @import("std");


const Token = union(enum) {
    identifier: []const u8



}








const Lexer = struct {
    /// The content that is parsed
    content: []const u8,
    /// Current position inside content
    index: usize,
    alloc: std.mem.Allocator,
    
    tokens:std.ArrayList(Token),

    const Self = @This();

    /// content must be valid as long as
    pub fn init(content: []const u8, alloc: std.mem.Allocator) !Lexer {
        return .{ .content = content, .index = 0, .alloc = alloc, .tokens = std.ArrayList(Token).init(alloc)};
    }

    pub fn tokenize(self:Self) std.ArrayList( {

    }

};
