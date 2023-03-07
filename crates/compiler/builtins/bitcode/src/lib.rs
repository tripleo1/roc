pub const HOST_WASM: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/builtins-wasm32.o"));
// TODO: in the future, we should use Zig's cross-compilation to generate and store these
// for all targets, so that we can do cross-compilation!
#[cfg(unix)]
pub const HOST_UNIX: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/builtins-host.o"));
#[cfg(windows)]
pub const HOST_WINDOWS: &[u8] =
    include_bytes!(concat!(env!("OUT_DIR"), "/builtins-windows-x86_64.obj"));
