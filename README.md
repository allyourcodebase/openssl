# openssl zig package

This is openssl ported to the Zig Build System.

## Status

I was able to use this to build [CPython](https://github.com/thejoshwolfe/cpython) for x86_64-linux.

Adding support for other operating systems and CPU architectures is straightforward and will
require fiddling with the build script to take into account the target.

## Zig version compatibility

- `0.16.x`
- `0.15.x`
- `0.14.x`

## Anti-Endorsement

I do not endorse openssl. I think it is a pile of trash. My motivation for this
project is because it is a dependency of CPython, which is a dependency of the
most active YouTube downloader, [ytdlp](https://github.com/yt-dlp/yt-dlp).
