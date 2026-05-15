use std::sync::Mutex;

use anyhow::Result;
use flutter_rust_bridge::frb;
use once_cell::sync::OnceCell;
use tracing_subscriber::layer::Context;
use tracing_subscriber::prelude::*;

use crate::frb_generated::StreamSink;

/// 跨橋傳給 Dart 的 log event。對應 Dart 的 `Logger('rust.<target>').log(level, message, ...)`。
#[derive(Clone)]
#[frb]
pub struct LogEvent {
    pub timestamp_ms: i64,
    /// "ERROR" | "WARN" | "INFO" | "DEBUG" | "TRACE"
    pub level: String,
    /// tracing target,例如 "mitm" / "ca" / "cert_store" / "panic"
    pub target: String,
    pub message: String,
}

// Store a type-erased sender so ForwardLayer doesn't need LogEvent: SseEncode at the call site.
type ForwardFn = Box<dyn Fn(LogEvent) + Send + Sync>;

static FORWARD_SINK: OnceCell<Mutex<Option<ForwardFn>>> = OnceCell::new();
static INIT: OnceCell<()> = OnceCell::new();

/// Dart 端在 `main()` 內呼叫一次。重複呼叫只會覆蓋現有 sink(idempotent)。
pub fn start_log_stream(sink: StreamSink<LogEvent>) -> Result<()> {
    let slot = FORWARD_SINK.get_or_init(|| Mutex::new(None));
    *slot.lock().unwrap() = Some(Box::new(move |event| {
        let _ = sink.add(event);
    }));
    init_tracing_once();
    Ok(())
}

/// 安裝 tracing 全域 subscriber(只執行一次)。
/// - 保留 stdout `fmt::layer()` 讓 `cargo run` 階段仍可見;
/// - 加上 `ForwardLayer` 把事件轉送到 Dart;
/// - 設定 panic hook 把 Rust panic 訊息也轉成 `tracing::error!`。
pub(crate) fn init_tracing_once() {
    INIT.get_or_init(|| {
        let filter = tracing_subscriber::EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info"));

        let _ = tracing_subscriber::registry()
            .with(filter)
            .with(tracing_subscriber::fmt::layer())
            .with(ForwardLayer)
            .try_init();

        std::panic::set_hook(Box::new(|info| {
            tracing::error!(target: "panic", "{info}");
        }));
    });
}

struct ForwardLayer;

impl<S> tracing_subscriber::Layer<S> for ForwardLayer
where
    S: tracing::Subscriber,
{
    fn on_event(&self, event: &tracing::Event<'_>, _ctx: Context<'_, S>) {
        let sink_slot = match FORWARD_SINK.get() {
            Some(s) => s,
            None => return,
        };
        let guard = sink_slot.lock().unwrap();
        let forward = match guard.as_ref() {
            Some(f) => f,
            None => return,
        };

        let metadata = event.metadata();
        let level = metadata.level().as_str().to_string();
        let target = metadata.target().to_string();

        let mut visitor = MessageVisitor::default();
        event.record(&mut visitor);
        let message = visitor.finish();

        let now_ms = chrono::Utc::now().timestamp_millis();
        forward(LogEvent {
            timestamp_ms: now_ms,
            level,
            target,
            message,
        });
    }
}

#[derive(Default)]
struct MessageVisitor {
    message: Option<String>,
    fields: Vec<(String, String)>,
}

impl MessageVisitor {
    fn finish(mut self) -> String {
        let mut out = self.message.take().unwrap_or_default();
        for (k, v) in self.fields {
            out.push(' ');
            out.push_str(&k);
            out.push('=');
            out.push_str(&v);
        }
        out
    }
}

impl tracing::field::Visit for MessageVisitor {
    fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
        if field.name() == "message" {
            self.message = Some(format!("{value:?}"));
        } else {
            self.fields
                .push((field.name().to_string(), format!("{value:?}")));
        }
    }

    fn record_str(&mut self, field: &tracing::field::Field, value: &str) {
        if field.name() == "message" {
            self.message = Some(value.to_string());
        } else {
            self.fields
                .push((field.name().to_string(), value.to_string()));
        }
    }
}
