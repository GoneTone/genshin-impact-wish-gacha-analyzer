use flutter_rust_bridge::frb;

/// PoC sanity-check function. Removed in Task 8 once real APIs land.
#[frb(sync)]
pub fn ping() -> String {
    "pong".to_string()
}
