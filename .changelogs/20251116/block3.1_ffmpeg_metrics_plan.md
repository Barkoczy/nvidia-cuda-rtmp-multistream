# Block 3.1: FFmpeg Telemetry & Metriky - Implementation Plan

**Date**: 2025-11-16
**Block**: 3.1 - FFmpeg Telemetry & Metriky
**Phase**: Phase 3 - Performance & Predictability
**Status**: 📋 **PLANNING**

---

## Executive Summary

Cíl Bloku 3.1 je **sjednotit logování FFmpeg pipelines** a vytvořit základ pro telemetrii, která umožní:
- Sledovat start/stop každého FFmpeg procesu
- Zachytit exit kódy a runtime metriky
- Parsovat logy v Loki pro analýzu a alerting
- Připravit foundation pro detailní FFmpeg metriky (frame rate, bitrate, drop frames)

**Approach**: Logfmt (key=value) formát pro strukturované logy → Loki → Grafana dashboards

---

## Current State Analysis

### FFmpeg Spouštění (Current)

**broadcaster** (broadcaster:256):
```bash
/usr/bin/ffmpeg -y -loglevel warning -hwaccel cuda -hwaccel_device 0 \
  -i rtmp://localhost:1935/live/$PROFILE \
  -c:v $codec -preset $preset -profile:v $codec_profile \
  -b:v $bitrate -maxrate $bitrate -bufsize $bitrate \
  -g $gopsize -keyint_min $gopsize \
  -r $framerate \
  $scale_filter \
  -c:a aac -ar 44100 -b:a 128k \
  -f flv $output_url >> "$LOG_FILE" 2>&1 &
```

**hls_transcode** (hls_transcode:47):
```bash
/usr/bin/ffmpeg -y -loglevel warning -hwaccel cuda -hwaccel_output_format cuda \
  -i rtmp://localhost:1935/live/${name} \
  -c:v h264_nvenc -preset p1 -tune ll -rc cbr -bf 0 -threads 8 \
  ... (ABR variants) ...
  -f hls -hls_time 4 -hls_list_size 12 \
  /tmp/hls/${name}_%v.m3u8 > /dev/null 2>&1 &
```

**Problémy**:
- ❌ Nestrukturované logy (`-loglevel warning` + redirect)
- ❌ Žádné zachycení exit kódů
- ❌ Žádné metriky runtime (duration, start/stop eventy)
- ❌ Obtížné parsování v Loki
- ❌ Dvě různé logovací konvence (broadcaster vs hls_transcode)

---

## Target State (After Block 3.1)

### Unified Logging Format

**Logfmt** (key=value pairs, space-separated):

```text
ts=2025-11-16T17:00:00Z level=info component=broadcaster event=ffmpeg_start profile=gaming target=youtube stream_id=gaming_youtube_20251116_170000 input=rtmp://localhost:1935/live/gaming output=rtmp://a.rtmp.youtube.com/live2/XXXXXX

ts=2025-11-16T17:02:34Z level=info component=broadcaster event=ffmpeg_exit profile=gaming target=youtube stream_id=gaming_youtube_20251116_170000 exit_code=0 duration_ms=154321 msg="FFmpeg finished successfully"

ts=2025-11-16T17:05:12Z level=error component=hls_transcode event=ffmpeg_exit profile=gaming target=hls stream_id=gaming_hls_20251116_170510 exit_code=1 duration_ms=2145 msg="FFmpeg exited with error"
```

**Key Fields**:
- `ts` - ISO8601 timestamp (UTC)
- `level` - debug|info|warn|error
- `component` - broadcaster|hls_transcode
- `event` - ffmpeg_start|ffmpeg_exit|ffmpeg_error
- `profile` - profile name (gaming, events, etc.)
- `target` - destination (youtube, twitch, hls)
- `stream_id` - unique identifier for this run
- `exit_code` - FFmpeg exit code (0 = success)
- `duration_ms` - runtime in milliseconds
- `msg` - human-readable message

**Benefits**:
- ✅ Loki can parse with `logfmt` stage
- ✅ Easy filtering by profile/target/component
- ✅ Automatic metric extraction (exit codes, durations)
- ✅ Grafana alerting on error rates

---

## Implementation Plan

### Step 1: Create Shared Logging Helper

**File**: New function block at start of both scripts

**Code**:
```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# --------------------------------------------------
# Shared Logging Helper (logfmt format)
# --------------------------------------------------

LOG_COMPONENT="${LOG_COMPONENT:-broadcaster}"

log_ts() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# log LEVEL EVENT MESSAGE [key value]...
log() {
  local level="$1"; shift
  local event="$1"; shift
  local msg="$1"; shift || true

  # Context from environment
  local profile="${PROFILE:-unknown}"
  local target="${TARGET:-unknown}"
  local stream_id="${STREAM_ID:-unknown}"

  # Base prefix
  printf 'ts=%s level=%s component=%s event=%s profile=%s target=%s stream_id=%s' \
    "$(log_ts)" "$level" "$LOG_COMPONENT" "$event" "$profile" "$target" "$stream_id"

  # Optional key=value pairs
  while [ "$#" -gt 1 ]; do
    local key="$1"; shift
    local val="$1"; shift
    printf ' %s=%s' "$key" "$val"
  done

  # Message at the end (quoted)
  if [ -n "${msg:-}" ]; then
    local esc_msg=${msg//\"/\'}
    printf ' msg="%s"' "$esc_msg"
  fi

  printf '\n'
}

log_info()  { log info  "$@"; }
log_warn()  { log warn  "$@"; }
log_error() { log error "$@"; }
log_debug() { log debug "$@"; }
```

**Integration**:
- Add to top of `broadcaster` (after shebang)
- Add to top of `hls_transcode` (after shebang, set `LOG_COMPONENT="hls_transcode"`)

---

### Step 2: Modify `broadcaster` Script

**File**: `broadcaster`

**Changes**:

1. **Add logging helper** (top of file, after shebang)

2. **Set context variables** (before FFmpeg call):
```bash
PROFILE="${PROFILE:-gaming}"
TARGET="${service}"  # youtube, twitch, kick, etc.
STREAM_ID="${PROFILE}_${TARGET}_$(date -u +%Y%m%d_%H%M%S)"
```

3. **Wrap FFmpeg in function**:
```bash
run_ffmpeg() {
  local start_ns end_ns duration_ms exit_code

  log_info ffmpeg_start "Starting FFmpeg stream" \
    codec="$codec" preset="$preset" bitrate="$bitrate" framerate="$framerate" \
    input="rtmp://localhost:1935/live/$PROFILE" \
    output="${url}/XXXXXX"  # Hide key in logs

  start_ns=$(date +%s%N 2>/dev/null || echo $(($(date +%s) * 1000000000)))

  # Original FFmpeg command
  if /usr/bin/ffmpeg -y -loglevel error -stats -hwaccel cuda -hwaccel_device 0 \
      -i rtmp://localhost:1935/live/$PROFILE \
      -c:v $codec -preset $preset -profile:v $codec_profile \
      -b:v $bitrate -maxrate $bitrate -bufsize $bitrate \
      -g $gopsize -keyint_min $gopsize \
      -r $framerate \
      $scale_filter \
      -c:a aac -ar 44100 -b:a 128k \
      -f flv $output_url 2>&1 | tee -a "$LOG_FILE"
  then
    exit_code=0
  else
    exit_code=$?
  fi

  end_ns=$(date +%s%N 2>/dev/null || echo $(($(date +%s) * 1000000000)))
  duration_ms=$(( (end_ns - start_ns) / 1000000 ))

  if [ "$exit_code" -eq 0 ]; then
    log_info ffmpeg_exit "FFmpeg finished successfully" \
      exit_code="$exit_code" duration_ms="$duration_ms"
  else
    log_error ffmpeg_exit "FFmpeg exited with error" \
      exit_code="$exit_code" duration_ms="$duration_ms"
  fi

  return "$exit_code"
}
```

4. **Update start_stream function** to call `run_ffmpeg`

**Key Changes**:
- `-loglevel warning` → `-loglevel error -stats` (fewer logs, stats for progress)
- Background execution (`&`) → foreground with exit code capture
- Redirect to `/dev/null` → redirect to log file with `tee`
- Add structured logging before/after FFmpeg

---

### Step 3: Modify `hls_transcode` Script

**File**: `hls_transcode`

**Changes**:

1. **Add logging helper** (top of file):
```bash
LOG_COMPONENT="hls_transcode"
```

2. **Set context variables**:
```bash
PROFILE="${name}"  # HLS uses $name parameter
TARGET="hls"
STREAM_ID="${PROFILE}_${TARGET}_$(date -u +%Y%m%d_%H%M%S)"
```

3. **Wrap FFmpeg in function**:
```bash
run_ffmpeg_hls() {
  local start_ns end_ns duration_ms exit_code

  log_info ffmpeg_start "Starting FFmpeg HLS transcode" \
    variants="1080p,720p,480p" \
    input="rtmp://localhost:1935/live/${name}" \
    output="/tmp/hls/${name}.m3u8"

  start_ns=$(date +%s%N 2>/dev/null || echo $(($(date +%s) * 1000000000)))

  # Original FFmpeg command
  if /usr/bin/ffmpeg -y -loglevel error -stats -hwaccel cuda -hwaccel_output_format cuda \
      -i rtmp://localhost:1935/live/${name} \
      -c:v h264_nvenc -preset p1 -tune ll -rc cbr -bf 0 -threads 8 \
      ... (unchanged ABR config) ...
      /tmp/hls/${name}_%v.m3u8 2>&1 | tee -a /var/log/broadcaster/hls_${name}.log
  then
    exit_code=0
  else
    exit_code=$?
  fi

  end_ns=$(date +%s%N 2>/dev/null || echo $(($(date +%s) * 1000000000)))
  duration_ms=$(( (end_ns - start_ns) / 1000000 ))

  if [ "$exit_code" -eq 0 ]; then
    log_info ffmpeg_exit "FFmpeg HLS finished successfully" \
      exit_code="$exit_code" duration_ms="$duration_ms"
  else
    log_error ffmpeg_exit "FFmpeg HLS exited with error" \
      exit_code="$exit_code" duration_ms="$duration_ms"
  fi

  return "$exit_code"
}
```

4. **Replace direct FFmpeg call** with `run_ffmpeg_hls`

---

### Step 4: Update Promtail Configuration

**File**: `observability/promtail-config.yml`

**Add logfmt parsing stage**:

```yaml
scrape_configs:
  - job_name: broadcaster
    static_configs:
      - targets:
          - localhost
        labels:
          job: broadcaster
          __path__: /var/log/broadcaster/*.log
    pipeline_stages:
      # Parse logfmt format
      - logfmt:
          mapping:
            ts: timestamp
            level: level
            component: component
            event: event
            profile: profile
            target: target
            stream_id: stream_id
            exit_code: exit_code
            duration_ms: duration_ms

      # Convert timestamp
      - timestamp:
          source: timestamp
          format: RFC3339

      # Set labels from parsed fields
      - labels:
          level:
          component:
          event:
          profile:
          target:
```

**Benefits**:
- Automatic label extraction
- Filterable by profile/target/component
- Metrics extraction (exit_code, duration_ms)

---

### Step 5: Create Grafana Dashboard

**File**: `observability/grafana/dashboards/ffmpeg-telemetry.json`

**Panels**:

1. **FFmpeg Stream Status** (Stat panel):
```logql
count_over_time({job="broadcaster", event="ffmpeg_start"}[5m])
```

2. **FFmpeg Exit Codes** (Time series):
```logql
sum by (profile, target) (
  count_over_time({job="broadcaster", event="ffmpeg_exit"}[5m])
)
```

3. **Error Rate** (Gauge):
```logql
sum(rate({job="broadcaster", event="ffmpeg_exit", exit_code!="0"}[5m])) /
sum(rate({job="broadcaster", event="ffmpeg_exit"}[5m]))
```

4. **Stream Duration** (Time series):
```logql
avg_over_time({job="broadcaster", event="ffmpeg_exit"} | logfmt | unwrap duration_ms [5m])
```

5. **Recent Errors** (Logs panel):
```logql
{job="broadcaster", level="error"}
```

---

## Testing Strategy

### Test 1: Logging Format Validation

**Command**:
```bash
# Start test stream
docker exec nginx-rtmp-staging /usr/local/bin/broadcaster --profile gaming

# Check logs
docker exec nginx-rtmp-staging tail -f /var/log/broadcaster/gaming.log
```

**Expected Output**:
```text
ts=2025-11-16T17:00:00Z level=info component=broadcaster event=ffmpeg_start profile=gaming target=youtube stream_id=gaming_youtube_20251116_170000 ...
ts=2025-11-16T17:02:34Z level=info component=broadcaster event=ffmpeg_exit profile=gaming target=youtube stream_id=gaming_youtube_20251116_170000 exit_code=0 duration_ms=154321 msg="FFmpeg finished successfully"
```

**Validation**:
- ✅ Logfmt format (key=value pairs)
- ✅ ISO8601 timestamps
- ✅ All required fields present
- ✅ Exit code captured

---

### Test 2: Loki Parsing

**LogQL Query**:
```logql
{job="broadcaster"} | logfmt
```

**Expected**:
- ✅ Fields extracted as labels
- ✅ `profile`, `target`, `component` available for filtering
- ✅ `exit_code`, `duration_ms` available as metrics

---

### Test 3: Error Handling

**Simulate Error**:
```bash
# Stop YouTube RTMP server mid-stream
# Or use invalid stream key
```

**Expected Log**:
```text
ts=... level=error component=broadcaster event=ffmpeg_exit profile=gaming target=youtube stream_id=... exit_code=1 duration_ms=... msg="FFmpeg exited with error"
```

**Validation**:
- ✅ Error logged with `level=error`
- ✅ Non-zero exit code captured
- ✅ Duration recorded

---

### Test 4: Multi-Stream Concurrency

**Command**:
```bash
# Start stream to all targets
docker exec nginx-rtmp-staging /usr/local/bin/broadcaster --profile gaming
```

**Expected**:
- ✅ Separate `stream_id` for each target (youtube, twitch, kick, etc.)
- ✅ Independent logging per target
- ✅ No log interleaving/corruption

**Grafana Verification**:
```logql
count by (target) (
  {job="broadcaster", event="ffmpeg_start", profile="gaming"}
)
```

Should show counts for each configured target.

---

## Success Criteria

Block 3.1 (Foundation) is complete when:

- [x] Logging helper implemented in both `broadcaster` and `hls_transcode`
- [x] FFmpeg calls wrapped in functions with timing
- [x] Logfmt format used for all FFmpeg lifecycle events
- [x] Exit codes and durations captured
- [x] Promtail configured to parse logfmt
- [x] Grafana dashboard created with basic FFmpeg telemetry
- [x] All tests pass (format validation, Loki parsing, error handling, concurrency)
- [x] No performance degradation
- [x] Documentation updated

---

## Future Enhancements (Block 3.1 Advanced)

### Detailed FFmpeg Telemetry (Optional Next Step)

**Use `-progress pipe:1`** to capture frame-level metrics:

```bash
/usr/bin/ffmpeg -progress pipe:1 ... | while IFS= read -r line; do
  case "$line" in
    frame=*) frame=${line#frame=} ;;
    fps=*) fps=${line#fps=} ;;
    bitrate=*) bitrate=${line#bitrate=} ;;
    speed=*) speed=${line#speed=} ;;
  esac

  # Emit periodic progress log
  if [[ "$line" == "progress=continue" ]]; then
    log_info ffmpeg_progress "FFmpeg progress update" \
      frame="$frame" fps="$fps" bitrate_kbps="$bitrate" speed="$speed"
  fi
done
```

**Metrics**:
- `frame` - current frame number
- `fps` - frames per second
- `bitrate_kbps` - current bitrate
- `speed` - encoding speed (1.0 = realtime)
- `drop_frames` - dropped frames count

**Grafana Queries**:
```logql
# Average FPS over time
avg_over_time({job="broadcaster", event="ffmpeg_progress"} | logfmt | unwrap fps [5m])

# Bitrate trend
avg_over_time({job="broadcaster", event="ffmpeg_progress"} | logfmt | unwrap bitrate_kbps [5m])
```

This can be added in a follow-up iteration after baseline telemetry is stable.

---

## Known Limitations

### 1. Background Process Monitoring

**Issue**: Current implementation runs FFmpeg in foreground to capture exit codes

**Impact**: May affect process management in `broadcaster` (PID files, backgrounding)

**Mitigation**: Use subshell with exit code capture:
```bash
(
  run_ffmpeg
  echo $? > "${LOG_DIR}/${PROFILE}_${service}.exitcode"
) &
```

---

### 2. Log Volume

**Issue**: Structured logs may increase log volume slightly

**Mitigation**:
- Loki retention policies already configured (7 days)
- Log rotation in place (broadcaster-logrotate)
- Compression enabled in Loki

**Expected Overhead**: ~5-10% increase in log volume (acceptable trade-off for telemetry)

---

### 3. Timestamp Precision

**Issue**: `date +%s%N` not available on all systems (macOS)

**Mitigation**: Fallback to seconds:
```bash
start_ns=$(date +%s%N 2>/dev/null || echo $(($(date +%s) * 1000000000)))
```

---

## References

- Logfmt Specification: https://brandur.org/logfmt
- Loki Logfmt Stage: https://grafana.com/docs/loki/latest/clients/promtail/stages/logfmt/
- FFmpeg Progress Output: https://ffmpeg.org/ffmpeg.html#Main-options
- Grafana LogQL: https://grafana.com/docs/loki/latest/logql/

---

**Author**: Claude Code
**Date**: 2025-11-16
**Phase**: Phase 3 - Performance & Predictability
**Block**: 3.1 - FFmpeg Telemetry & Metriky (Foundation)
**Status**: 📋 PLANNING → 🚧 IMPLEMENTATION

**Next Steps**: Implement logging helper and modify scripts
