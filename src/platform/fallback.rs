use std::path::PathBuf;

/// Unsupported platform stub.
pub fn foreground_process_name(_child_pid: u32) -> Option<String> {
    None
}

/// Unsupported platform stub.
pub fn process_cwd(_pid: u32) -> Option<PathBuf> {
    None
}
