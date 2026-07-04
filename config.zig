const std = @import("std");

/// One perlasm script invocation. Most scripts produce a file named after
/// the script, but some generate different code depending on the requested
/// output name (e.g. sha512-x86_64.pl generates both sha256-x86_64.s and
/// sha512-x86_64.s), so the output basename is stored explicitly.
pub const PerlScript = struct {
    /// Script path relative to the openssl root, without the .pl extension.
    path: []const u8,
    /// Basename of the generated .s file, without the extension.
    output: []const u8,

    fn script(comptime path: []const u8) PerlScript {
        // Hand-rolled basename: std.fs.path.basename exceeds the comptime
        // branch quota when evaluated once per script.
        var i = path.len;
        while (i > 0 and path[i - 1] != '/') i -= 1;
        return .{ .path = path, .output = path[i..] };
    }

    fn scriptAs(path: []const u8, output: []const u8) PerlScript {
        return .{ .path = path, .output = output };
    }
};

/// Per-architecture asm build data, mirroring upstream crypto/*/build.info
/// ($*ASM_<arch> / $*DEF_<arch>). Per-arch, not per-OS: every OS variant of an
/// arch shares the same CPU asm; the OS axis only picks the perlasm flavour and
/// OS-specific C sources (see Variant / build.zig).
pub const ArchConfig = struct {
    /// The -D macros (without the -D) that enable this arch's asm, one per
    /// $*DEF_<asm_arch> knob upstream. A macro without its asm fails to link;
    /// asm without its macro is dead weight (or a duplicate symbol where the
    /// asm replaces a C file). Sub-features that dispatch on cpuid at runtime
    /// need no macro of their own: on x86_64, AES_ASM also lights up the
    /// VAES/VPCLMULQDQ AVX512 AES-GCM path (VAES_GCM_ENABLED, see
    /// cipher_aes_gcm_hw_vaes_avx512.inc) and OPENSSL_BN_ASM_MONT the AVX512
    /// RSAZ path (RSAZ_ENABLED, see crypto/bn/rsaz_exp.h).
    defines: []const []const u8,
    /// perlasm scripts to generate and compile.
    scripts: []const PerlScript,
    /// Arch-specific C sources (relative to upstream crypto/): the asm-backed
    /// glue this arch compiles, plus the C files the *other* arch replaces with
    /// asm but this one keeps. The C fallbacks the asm stands in for are simply
    /// not listed.
    sources: []const []const u8,
    /// Generated-file extension. The aarch64 asm needs the C preprocessor
    /// (#include "arm_arch.h", BTI/PAC macros), hence ".S"; the x86_64 asm
    /// contains no preprocessor directives.
    asm_ext: []const u8,
};

const aarch64_config = ArchConfig{
    .defines = &.{
        "OPENSSL_CPUID_OBJ", "OPENSSL_BN_ASM_MONT", "BSAES_ASM",     "VPAES_ASM",
        "ECP_NISTZ256_ASM",  "ECP_SM2P256_ASM",     "MD5_ASM",       "POLY1305_ASM",
        "KECCAK1600_ASM",    "SHA1_ASM",            "SHA256_ASM",    "SHA512_ASM",
        "OPENSSL_SM3_ASM",   "SM4_ASM",             "VPSM4_ASM",
    },
    .scripts = &.{
        // Hardware-crypto (aes/ghash/gcm) and chacha asm dispatch at runtime
        // via OPENSSL_armcap_P, so they carry no define and always compile.
        .script("crypto/aes/asm/aesv8-armx"),
        .script("crypto/chacha/asm/chacha-armv8"),
        .script("crypto/chacha/asm/chacha-armv8-sve"),
        .script("crypto/modes/asm/ghashv8-armx"),
        .script("crypto/modes/asm/aes-gcm-armv8_64"),
        .script("crypto/modes/asm/aes-gcm-armv8-unroll8_64"),
        .script("crypto/arm64cpuid"),
        .script("crypto/bn/asm/armv8-mont"),
        .script("crypto/aes/asm/bsaes-armv8"),
        .script("crypto/aes/asm/vpaes-armv8"),
        .script("crypto/ec/asm/ecp_nistz256-armv8"),
        .script("crypto/ec/asm/ecp_sm2p256-armv8"),
        .script("crypto/md5/asm/md5-aarch64"),
        .script("crypto/poly1305/asm/poly1305-armv8"),
        .script("crypto/sha/asm/keccak1600-armv8"),
        .script("crypto/sha/asm/sha1-armv8"),
        // sha512-armv8.pl emits sha256 or sha512 depending on the output name.
        .scriptAs("crypto/sha/asm/sha512-armv8", "sha256-armv8"),
        .script("crypto/sha/asm/sha512-armv8"),
        .script("crypto/sm3/asm/sm3-armv8"),
        .script("crypto/sm4/asm/sm4-armv8"),
        .script("crypto/sm4/asm/vpsm4-armv8"),
        .script("crypto/sm4/asm/vpsm4_ex-armv8"),
    },
    .sources = &.{
        // The C files x86_64 replaces with asm but aarch64 always compiles
        // (see $*ASM_aarch64 in crypto/*/build.info).
        "aes/aes_cbc.c",
        "aes/aes_core.c",
        "bn/bn_asm.c",
        "camellia/camellia.c",
        "camellia/cmll_cbc.c",
        "rc4/rc4_enc.c",
        "rc4/rc4_skey.c",
        "whrlpool/wp_block.c",
        // asm-backed C glue.
        "armcap.c",
        "ec/ecp_nistz256.c",
        "ec/ecp_sm2p256.c",
        "ec/ecp_sm2p256_table.c",
    },
    .asm_ext = ".S",
};

const x86_64_config = ArchConfig{
    .defines = &.{
        "OPENSSL_CPUID_OBJ",   "AES_ASM",              "BSAES_ASM",           "VPAES_ASM",
        "OPENSSL_BN_ASM_MONT", "OPENSSL_BN_ASM_MONT5", "OPENSSL_BN_ASM_GF2m", "CMLL_ASM",
        "GHASH_ASM",           "MD5_ASM",              "ECP_NISTZ256_ASM",    "X25519_ASM",
        "POLY1305_ASM",        "RC4_ASM",              "KECCAK1600_ASM",      "SHA1_ASM",
        "SHA256_ASM",          "SHA512_ASM",           "WHIRLPOOL_ASM",       "OPENSSL_IA32_SSE2",
    },
    .scripts = &.{
        // chacha-x86_64.s carries no define (it replaces chacha_enc.c outright).
        .script("crypto/chacha/asm/chacha-x86_64"),
        .script("crypto/x86_64cpuid"),
        .script("crypto/aes/asm/aes-x86_64"),
        .script("crypto/aes/asm/aesni-x86_64"),
        .script("crypto/aes/asm/aesni-mb-x86_64"),
        .script("crypto/aes/asm/aesni-sha1-x86_64"),
        .script("crypto/aes/asm/aesni-sha256-x86_64"),
        .script("crypto/aes/asm/bsaes-x86_64"),
        .script("crypto/aes/asm/vpaes-x86_64"),
        .script("crypto/bn/asm/x86_64-mont"),
        .script("crypto/bn/asm/rsaz-x86_64"),
        .script("crypto/bn/asm/rsaz-avx2"),
        .script("crypto/bn/asm/rsaz-2k-avx512"),
        .script("crypto/bn/asm/rsaz-3k-avx512"),
        .script("crypto/bn/asm/rsaz-4k-avx512"),
        .script("crypto/bn/asm/x86_64-mont5"),
        .script("crypto/bn/asm/x86_64-gf2m"),
        .script("crypto/camellia/asm/cmll-x86_64"),
        .script("crypto/modes/asm/ghash-x86_64"),
        .script("crypto/modes/asm/aesni-gcm-x86_64"),
        .script("crypto/modes/asm/aes-gcm-avx512"),
        .script("crypto/md5/asm/md5-x86_64"),
        .script("crypto/ec/asm/ecp_nistz256-x86_64"),
        .script("crypto/ec/asm/x25519-x86_64"),
        .script("crypto/poly1305/asm/poly1305-x86_64"),
        .script("crypto/rc4/asm/rc4-x86_64"),
        .script("crypto/rc4/asm/rc4-md5-x86_64"),
        .script("crypto/sha/asm/keccak1600-x86_64"),
        .script("crypto/sha/asm/sha1-x86_64"),
        .script("crypto/sha/asm/sha1-mb-x86_64"),
        // sha512-x86_64.pl emits sha256 or sha512 depending on the output name.
        .scriptAs("crypto/sha/asm/sha512-x86_64", "sha256-x86_64"),
        .script("crypto/sha/asm/sha256-mb-x86_64"),
        .script("crypto/sha/asm/sha512-x86_64"),
        .script("crypto/whrlpool/asm/wp-x86_64"),
    },
    .sources = &.{
        // x86_64-only C: x86_64-gcc.c replaces bn_asm.c; rsaz_exp*.c self-gate
        // on RSAZ_ENABLED; ecp_nistz256.c is the asm glue.
        "bn/asm/x86_64-gcc.c",
        "bn/rsaz_exp.c",
        "bn/rsaz_exp_x2.c",
        "ec/ecp_nistz256.c",
    },
    .asm_ext = ".s",
};

pub const Variant = struct {
    arch: std.Target.Cpu.Arch,
    os: std.Target.Os.Tag,
    /// The perlasm flavour: for aarch64 see crypto/perlasm/arm-xlate.pl
    /// (linux64/ios64/win64), for x86_64 see crypto/perlasm/x86_64-xlate.pl
    /// (elf/macosx/mingw64/nasm/masm).
    flavor: []const u8,
};

pub const variants = [_]Variant{
    .{ .arch = .x86_64, .os = .linux, .flavor = "elf" },
    .{ .arch = .x86_64, .os = .macos, .flavor = "macosx" },
    .{ .arch = .x86_64, .os = .windows, .flavor = "mingw64" },

    .{ .arch = .aarch64, .os = .linux, .flavor = "linux64" },
    .{ .arch = .aarch64, .os = .macos, .flavor = "ios64" },
    .{ .arch = .aarch64, .os = .windows, .flavor = "win64" },
};

pub fn archConfig(arch: std.Target.Cpu.Arch) ArchConfig {
    return switch (arch) {
        .aarch64 => aarch64_config,
        .x86_64 => x86_64_config,
        else => @panic("unsupported architecture for OpenSSL asm"),
    };
}

/// The directory under gen/ holding this variant's generated asm.
pub fn dirName(v: Variant, allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}-{s}", .{ @tagName(v.arch), @tagName(v.os) });
}

/// Upstream Configure target for this variant, used to produce the
/// configdata.pm the header templates are filled from. aarch64-windows has
/// no target in 3.3.2; mingw-arm64.conf (repo root) defines one and is
/// passed to Configure via --config.
pub fn configureTarget(v: Variant) []const u8 {
    return switch (v.os) {
        .linux => switch (v.arch) {
            .x86_64 => "linux-x86_64",
            .aarch64 => "linux-aarch64",
            else => @panic("unsupported architecture for OpenSSL configure"),
        },
        .macos => switch (v.arch) {
            .x86_64 => "darwin64-x86_64-cc",
            .aarch64 => "darwin64-arm64-cc",
            else => @panic("unsupported architecture for OpenSSL configure"),
        },
        .windows => switch (v.arch) {
            .x86_64 => "mingw64",
            .aarch64 => "mingw-arm64",
            else => @panic("unsupported architecture for OpenSSL configure"),
        },
        else => @panic("unsupported os for OpenSSL configure"),
    };
}

/// One file generated from an upstream template by util/dofile.pl (the
/// GENERATE rules in upstream build.info).
pub const Template = struct {
    /// Template path relative to the openssl root, without the .in extension.
    input: []const u8,
    /// Output path relative to the file's gen base: gen/shared/ for shared
    /// templates, gen/{arch}-{os}/ for variant templates (generate.zig
    /// prepends the base).
    output: []const u8,
    /// Whether the template calls oids_to_c (providers/common/der), which
    /// must be loaded with -Moids_to_c.
    oids: bool = false,

    fn tmpl(path: []const u8) Template {
        return .{ .input = path, .output = path };
    }

    fn der(comptime name: []const u8) Template {
        return .{
            .input = "providers/common/include/prov/der_" ++ name ++ ".h",
            .output = "include/prov/der_" ++ name ++ ".h",
            .oids = true,
        };
    }

    fn derGen(comptime name: []const u8) Template {
        return .{
            .input = "providers/common/der/der_" ++ name ++ "_gen.c",
            .output = "providers/common/der/der_" ++ name ++ "_gen.c",
            .oids = true,
        };
    }
};

/// Target-independent generated files, filled once from the x86_64-linux
/// configdata (they only depend on version fields, the disabled-feature set
/// and the util/perl code generators, all identical across variants).
pub const shared_templates = [_]Template{
    .tmpl("include/openssl/asn1.h"),
    .tmpl("include/openssl/asn1t.h"),
    .tmpl("include/openssl/bio.h"),
    .tmpl("include/openssl/cmp.h"),
    .tmpl("include/openssl/cms.h"),
    .tmpl("include/openssl/conf.h"),
    .tmpl("include/openssl/core_names.h"),
    .tmpl("include/openssl/crmf.h"),
    .tmpl("include/openssl/crypto.h"),
    .tmpl("include/openssl/ct.h"),
    .tmpl("include/openssl/err.h"),
    .tmpl("include/openssl/ess.h"),
    .tmpl("include/openssl/fipskey.h"),
    .tmpl("include/openssl/lhash.h"),
    .tmpl("include/openssl/ocsp.h"),
    .tmpl("include/openssl/opensslv.h"),
    .tmpl("include/openssl/pkcs12.h"),
    .tmpl("include/openssl/pkcs7.h"),
    .tmpl("include/openssl/safestack.h"),
    .tmpl("include/openssl/srp.h"),
    .tmpl("include/openssl/ssl.h"),
    .tmpl("include/openssl/ui.h"),
    .tmpl("include/openssl/x509.h"),
    .tmpl("include/openssl/x509_vfy.h"),
    .tmpl("include/openssl/x509v3.h"),
    .tmpl("include/internal/param_names.h"),
    .tmpl("crypto/params_idx.c"),
    .der("digests"),
    .der("dsa"),
    .der("ec"),
    .der("ecx"),
    .der("rsa"),
    .der("sm2"),
    .der("wrap"),
    .derGen("digests"),
    .derGen("dsa"),
    .derGen("ec"),
    .derGen("ecx"),
    .derGen("rsa"),
    .derGen("sm2"),
    .derGen("wrap"),
};

/// Target-dependent generated headers, filled per variant into
/// gen/{arch}-{os}/include/ (upstream generates these per Configure target:
/// bn_ops, sys_id and dso_scheme differ across our variants).
pub const variant_templates = [_]Template{
    .tmpl("include/openssl/configuration.h"),
    .tmpl("include/crypto/bn_conf.h"),
    .tmpl("include/crypto/dso_conf.h"),
};

/// Zig target triple for this variant, for the $CC the perlasm scripts probe
/// with. The probes must see the *target* toolchain: e.g. the mingw64 flavour
/// asks $CC for __USER_LABEL_PREFIX__ to decide symbol decoration.
pub fn zigTriple(v: Variant, allocator: std.mem.Allocator) ![]u8 {
    const os_suffix: []const u8 = switch (v.os) {
        .linux => "linux-gnu",
        .windows => "windows-gnu",
        .macos => "macos",
        else => @panic("unsupported os for OpenSSL asm"),
    };
    return std.fmt.allocPrint(allocator, "{s}-{s}", .{ @tagName(v.arch), os_suffix });
}
