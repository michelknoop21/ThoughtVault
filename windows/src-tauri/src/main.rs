#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // MCP clients start `ThoughtVault.exe --mcp` as a stdio server: no window, no single-instance check.
    if std::env::args().skip(1).any(|arg| arg == "--mcp") {
        std::process::exit(thoughtvault_lib::run_mcp_bridge());
    }
    thoughtvault_lib::run()
}
