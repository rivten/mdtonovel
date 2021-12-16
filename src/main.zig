const std = @import("std");

fn parseLines(buffer: []const u8) ![]const u8 {
    var line_it = std.mem.tokenize(buffer, "\n");
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    while (line_it.next()) |line| {
        if (line[0] == '-') {
            try result.appendSlice("\n--");
        }
        try result.appendSlice(line);
    }
    return result.items;
}

fn parseDialog(buffer: []const u8) ![]const u8 {
    std.debug.assert(buffer.len > 0 and buffer[0] == '"');
    var endOfDialogIndex = std.mem.indexOfScalar(u8, buffer[1..], '"').?;
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    {
        var buf: [5]u8 = undefined;
        var size = try std.unicode.utf8Encode('«', &buf);
        for (buf[0..size]) |c| {
            try result.append(c);
        }
    }
    const remaining = buffer[1..(endOfDialogIndex + 1)];
    const parsedLines = try parseLines(remaining);
    try result.appendSlice(parsedLines);
    {
        var buf: [5]u8 = undefined;
        var size = try std.unicode.utf8Encode('»', &buf);
        for (buf[0..size]) |c| {
            try result.append(c);
        }
    }

    return result.items;
}

pub fn main() anyerror!void {
    std.log.info("{s}", .{try parseDialog("\"bonjour\"")});
}

test "parseDialog" {
    try std.testing.expect(std.mem.eql(u8, try parseDialog("\"bonjour\""), "«bonjour»"));
    try std.testing.expect(std.mem.eql(u8, try parseDialog("\"bonjour\n- ça va ?\n- oui et toi Jean-Jacques ?\""), "«bonjour\n--- ça va ?\n--- oui et toi Jean-Jacques ?»"));
}
