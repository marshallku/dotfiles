# Render one `codex exec --json` event as a progress line (empty for events nobody needs).
# Shared by codex-exec.sh (live stderr) and codex-tail.sh (following a run from another pane).
# Every field is read from parsed JSON, so model text can never pass for a control line.
def clip($n): if (.|length) > $n then .[0:$n] + "…" else . end;
def firstline: (. // "") | split("\n")[0] | clip(200);
try (
    if .type == "thread.started" then "🧵 thread \(.thread_id)"
    elif .type == "turn.started" then "🟢 turn started"
    elif .type == "item.started" and .item.type == "command_execution" then
        "▶ " + ((.item.command // "") | sub("^/[^ ]*/(ba|z)?sh -lc "; "") | clip(160))
    elif .type == "item.completed" and .item.type == "command_execution" then
        "  ✓ exit \(.item.exit_code // "?")"
    elif .type == "item.completed" and .item.type == "agent_message" then
        "💬 " + (.item.text | firstline)
    elif .type == "item.completed" and .item.type == "reasoning" then
        "🧠 " + ((.item.text // .item.summary // "") | firstline)
    elif .type == "turn.completed" then
        "🔵 turn completed (\(.usage.input_tokens // 0) in / \(.usage.output_tokens // 0) out)"
    elif .type == "turn.failed" then
        "❌ turn failed: " + ((.error.message // "unknown") | firstline)
    elif .type == "error" then
        "❌ " + ((.message // "error") | firstline)
    else empty end
) catch empty
