const std = @import("std");

const Token = struct {
    tag: Tag,
    loc: Loc,

    const Loc = struct {
        start: usize,
        end: usize,
    };

    const Tag = enum {
        hashtag,
        dashDialogStart,
        text,
        quotationMark,
        underscore,
        eof,
    };
};

const Tokenizer = struct {
    buffer: [:0]const u8,
    index: usize,

    pub fn init(buffer: [:0]const u8) Tokenizer {
        return .{
            .buffer = buffer,
            .index = 0,
        };
    }

    const State = enum {
        start,
        newline,
        text,
    };

    pub fn next(self: *Tokenizer) Token {
        var state: State = .start;
        var result = Token{
            .tag = .eof,
            .loc = .{
                .start = self.index,
                .end = undefined,
            },
        };

        while (true) : (self.index += 1) {
            const c = self.buffer[self.index];
            switch (state) {
                .start => switch (c) {
                    0 => break,
                    '\n' => {
                        state = .newline;
                    },
                    '#' => {
                        result.tag = .hashtag;
                        self.index += 1;
                        break;
                    },
                    '_' => {
                        result.tag = .underscore;
                        self.index += 1;
                        break;
                    },
                    '"' => {
                        result.tag = .quotationMark;
                        self.index += 1;
                        break;
                    },
                    else => {
                        result.tag = .text;
                        state = .text;
                    },
                },
                .newline => switch (c) {
                    '-' => {
                        result.tag = .dashDialogStart;
                        self.index += 1;
                        break;
                    },
                    else => {
                        state = .start;
                    },
                },
                .text => switch (c) {
                    '\n', '_' => {
                        //self.index -= 1;
                        state = .start;
                        break;
                    },
                    else => {},
                },
            }
        }

        if (result.tag == .eof) {
            result.loc.start = self.index;
        }
        result.loc.end = self.index;
        return result;
    }
};

pub fn main() anyerror!void {
    const input = "# Le titre du chapitre\n\n\"bonjour\n- ça va ?\n- oui et toi _Jean-Jacques_ ?\"\n\"\"";
    var tokenizer = Tokenizer.init(input);

    var token = tokenizer.next();
    while (token.tag != .eof) : (token = tokenizer.next()) {
        std.log.info("{}", .{token});
    }
}

test "parseDialog" {}
