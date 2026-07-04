const std = @import("std");
const config = @import("./config.zig");

const Options = struct {
    openssl_root: []const u8,
    /// Absolute path to the Configure --config file (mingw-arm64.conf).
    /// Configure runs with its cwd inside the scratch dir, so a relative path
    /// would not resolve.
    conf: []const u8,
};

fn usageError() error{BadUsage} {
    std.log.err("usage: generate <openssl-root> [--config <file>]", .{});
    return error.BadUsage;
}

/// Regenerates every committed generated file, writing straight into the
/// source tree (cwd is the repo root): the perlasm output under gen/<arch>-<os>/
/// and the Configure/dofile template headers (per-variant headers under
/// gen/<arch>-<os>/include/, the shared target-independent templates once into
/// include/, crypto/ and providers/). Invoked by `zig build gen`; requires perl
/// and a POSIX sh on PATH.
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    var args = try init.minimal.args.iterateAllocator(arena);
    _ = args.skip();

    var openssl_root: ?[]const u8 = null;
    var conf_arg: []const u8 = "mingw-arm64.conf";
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--config")) {
            conf_arg = args.next() orelse return usageError();
        } else if (openssl_root == null) {
            openssl_root = arg;
        } else {
            return usageError();
        }
    }

    const opts = Options{
        .openssl_root = openssl_root orelse return usageError(),
        .conf = try std.Io.Dir.cwd().realPathFileAlloc(init.io, conf_arg, arena),
    };

    // Variants are generated sequentially. Running them concurrently would
    // spawn many `zig cc` assembler probes at once, which race on a cold zig
    // cache and fail intermittently on a fresh checkout; this is a rare
    // maintainer command, so wall-time does not justify the risk.
    for (config.variants) |v| {
        const output_folder = try std.fmt.allocPrint(arena, "gen/{s}", .{try config.dirName(v, arena)});
        try std.Io.Dir.cwd().createDirPath(init.io, output_folder);

        // The perlasm scripts probe the toolchain by running $CC: the x86_64
        // scripts ask the assembler its version to decide whether to emit
        // AVX/AVX512, and the mingw64 flavour asks for the target's
        // __USER_LABEL_PREFIX__. So the children inherit the full environment
        // (PATH in particular, or every probe silently fails) and CC points at
        // a compiler for the *variant's* target.
        var env: std.process.Environ.Map = .init(arena);
        for (init.environ_map.keys(), init.environ_map.values()) |key, value|
            try env.put(key, value);
        const cc = try std.fmt.allocPrint(arena, "zig cc -target {s}", .{try config.zigTriple(v, arena)});
        try env.put("CC", cc);
        try env.put("ASM", cc);

        // The target-independent templates are filled once, from x86_64-linux;
        // any variant produces identical output for them.
        const gen_shared = v.arch == .x86_64 and v.os == .linux;

        try generateVariant(init, opts, v, output_folder, gen_shared, &env);
    }
}

fn generateVariant(
    init: std.process.Init,
    opts: Options,
    v: config.Variant,
    output_folder: []const u8,
    gen_shared: bool,
    env: *const std.process.Environ.Map,
) !void {
    const ac = config.archConfig(v.arch);
    for (ac.scripts) |s|
        try generateOne(init, opts.openssl_root, v.flavor, output_folder, s, ac.asm_ext, env);
    try generateTemplates(init, opts, v, output_folder, gen_shared, env);
}

fn generateOne(
    init: std.process.Init,
    openssl_root: []const u8,
    flavor: []const u8,
    output_folder: []const u8,
    s: config.PerlScript,
    ext: []const u8,
    env: *const std.process.Environ.Map,
) !void {
    var step_arena = std.heap.ArenaAllocator.init(init.gpa);
    defer step_arena.deinit();
    const alloc = step_arena.allocator();

    const input_file = try std.fmt.allocPrint(alloc, "{s}/{s}.pl", .{ openssl_root, s.path });
    const output_file = try std.fmt.allocPrint(alloc, "{s}/{s}{s}", .{ output_folder, s.output, ext });

    const argv = [_][]const u8{ "perl", input_file, flavor, output_file };
    const res = try std.process.run(alloc, init.io, .{ .argv = &argv, .environ_map = env });
    if (res.stdout.len > 0)
        std.log.info("{s}", .{res.stdout});
    if (!res.term.success()) {
        if (res.stderr.len > 0)
            std.log.err("{s}", .{res.stderr});
        return error.PerlScriptFailed;
    }
    if (res.stderr.len > 0)
        std.log.warn("{s}: {s}", .{ s.path, res.stderr });
    std.log.info("generated {s}", .{output_file});
}

/// Runs Configure out-of-tree to produce this variant's configdata.pm, then
/// fills the target-dependent headers into gen/<arch>-<os>/include/. The
/// x86_64-linux variant additionally fills the target-independent templates
/// checked into include/, crypto/ and providers/ (see config.shared_templates).
fn generateTemplates(
    init: std.process.Init,
    opts: Options,
    v: config.Variant,
    output_folder: []const u8,
    gen_shared: bool,
    env: *const std.process.Environ.Map,
) !void {
    var arena_state = std.heap.ArenaAllocator.init(init.gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    // Configure must run out-of-tree (cwd = scratch dir): it writes
    // configdata.pm plus a build-dir skeleton, none of which may land in the
    // zig package cache holding the upstream source.
    const scratch_rel = try std.fmt.allocPrint(alloc, ".zig-cache/openssl-configure/{s}-{s}", .{ @tagName(v.arch), @tagName(v.os) });
    try std.Io.Dir.cwd().createDirPath(init.io, scratch_rel);
    const scratch = try std.Io.Dir.cwd().realPathFileAlloc(init.io, scratch_rel, alloc);

    // Configure probes $CC for target predefines, so it must see the variant's
    // toolchain (env carries CC="zig cc -target <triple>"), not the host
    // compiler -- which may be absent or wrong for this variant.
    // enable-ec_nistp_64_gcc_128 matches the checked-in headers (build.zig
    // compiles ecp_nistp*.c, gated on it); --config supplies the mingw-arm64
    // target 3.3.2 lacks and is harmless for the stock targets.
    const configure = try std.fmt.allocPrint(alloc, "{s}/Configure", .{opts.openssl_root});
    const conf_flag = try std.fmt.allocPrint(alloc, "--config={s}", .{opts.conf});
    try runChecked(init, alloc, &.{
        "perl", configure, conf_flag, config.configureTarget(v), "enable-ec_nistp_64_gcc_128",
    }, .{ .path = scratch }, env);

    // configdata.pm records sourcedir relative to the scratch dir, but the
    // oids_to_c templates resolve it from dofile.pl's cwd, which is the openssl
    // root -- so rewrite it to ".".
    try runChecked(init, alloc, &.{
        "perl", "-pi", "-e", "s{^(\\s*\"sourcedir\" => ).*}{$1\".\",};", "configdata.pm",
    }, .{ .path = scratch }, env);

    for (config.variant_templates) |t| {
        const out_path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ output_folder, t.output });
        try generateTemplate(init, alloc, opts.openssl_root, scratch, t, out_path);
    }
    if (gen_shared) {
        for (config.shared_templates) |t| {
            const out_path = try std.fmt.allocPrint(alloc, "gen/shared/{s}", .{t.output});
            try generateTemplate(init, alloc, opts.openssl_root, scratch, t, out_path);
        }
    }
}

/// Fills one template with util/dofile.pl using the configdata.pm in `scratch`
/// and writes the captured stdout to `out_path`.
fn generateTemplate(
    init: std.process.Init,
    alloc: std.mem.Allocator,
    openssl_root: []const u8,
    scratch: []const u8,
    t: config.Template,
    out_path: []const u8,
) !void {
    const inc = try std.fmt.allocPrint(alloc, "-I{s}", .{scratch});
    const dofile = try std.fmt.allocPrint(alloc, "{s}/util/dofile.pl", .{openssl_root});
    const input = try std.fmt.allocPrint(alloc, "{s}.in", .{t.input});

    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(alloc, &.{ "perl", inc, "-Mconfigdata" });
    // oids_to_c.pm lives next to the der templates.
    if (t.oids)
        try argv.appendSlice(alloc, &.{ "-Iproviders/common/der", "-Moids_to_c" });
    // dofile.pl runs from the openssl root with a relative template path so its
    // "Generated by Makefile from <path>" comment matches upstream builds.
    try argv.appendSlice(alloc, &.{ dofile, "-oMakefile", input });

    const res = try std.process.run(alloc, init.io, .{
        .argv = argv.items,
        .cwd = .{ .path = openssl_root },
    });
    if (!res.term.success()) {
        if (res.stderr.len > 0)
            std.log.err("{s}", .{res.stderr});
        return error.TemplateFailed;
    }
    if (res.stderr.len > 0)
        std.log.warn("{s}: {s}", .{ t.input, res.stderr });

    if (std.fs.path.dirname(out_path)) |parent|
        try std.Io.Dir.cwd().createDirPath(init.io, parent);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out_path, .data = res.stdout });
    std.log.info("generated {s}", .{out_path});
}

fn runChecked(
    init: std.process.Init,
    alloc: std.mem.Allocator,
    argv: []const []const u8,
    cwd: std.process.Child.Cwd,
    env: *const std.process.Environ.Map,
) !void {
    const res = try std.process.run(alloc, init.io, .{ .argv = argv, .cwd = cwd, .environ_map = env });
    if (!res.term.success()) {
        if (res.stderr.len > 0)
            std.log.err("{s}", .{res.stderr});
        return error.CommandFailed;
    }
}
