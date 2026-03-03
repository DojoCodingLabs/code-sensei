#!/usr/bin/env bash
# Cross-platform date utilities for CodeSensei
# Supports: GNU date (Linux), BSD date (macOS), python3 fallback

# Get today's date in YYYY-MM-DD format (UTC)
date_today() {
  date -u '+%Y-%m-%d' 2>/dev/null || python3 -c "from datetime import datetime; print(datetime.utcnow().strftime('%Y-%m-%d'))"
}

# Get yesterday's date in YYYY-MM-DD format (UTC)
date_yesterday() {
  # Try GNU date first
  date -u -d 'yesterday' '+%Y-%m-%d' 2>/dev/null && return
  # Try BSD date (macOS)
  date -u -v-1d '+%Y-%m-%d' 2>/dev/null && return
  # Python fallback
  python3 -c "from datetime import datetime, timedelta; print((datetime.utcnow() - timedelta(days=1)).strftime('%Y-%m-%d'))" 2>/dev/null && return
  # Last resort: empty string
  echo ""
}

# Convert date string (YYYY-MM-DD) to epoch seconds
date_to_epoch() {
  local date_str="$1"
  # Try GNU date
  date -u -d "$date_str" '+%s' 2>/dev/null && return
  # Try BSD date (macOS)
  date -u -j -f '%Y-%m-%d' "$date_str" '+%s' 2>/dev/null && return
  # Python fallback
  python3 -c "from datetime import datetime; print(int(datetime.strptime('$date_str', '%Y-%m-%d').timestamp()))" 2>/dev/null && return
  echo "0"
}

# Get date N days ago in YYYY-MM-DD format (UTC)
date_days_ago() {
  local days="$1"
  # Try GNU date
  date -u -d "${days} days ago" '+%Y-%m-%d' 2>/dev/null && return
  # Try BSD date (macOS)
  date -u -v-${days}d '+%Y-%m-%d' 2>/dev/null && return
  # Python fallback
  python3 -c "from datetime import datetime, timedelta; print((datetime.utcnow() - timedelta(days=${days})).strftime('%Y-%m-%d'))" 2>/dev/null && return
  echo ""
}

# Get current UTC timestamp in ISO format
date_now_iso() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || python3 -c "from datetime import datetime; print(datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'))"
}
