# strava-my-feed-api.sh — sourced by strava-my-activities.sh (§2, api branch).
# Pages /api/v3/athlete/activities; appends NDJSON to $TMP/all.ndjson.
# Variables read from caller: TMP, MAX_PAGES, PER_PAGE, ACCESS_TOKEN, log, curl_retry.
# Variables written back: reached_end (set to 1 on natural end of feed).

log "fetching athlete activities via API (up to $MAX_PAGES pages of $PER_PAGE)..."
while [ "$page" -le "$MAX_PAGES" ]; do
  log "page $page: GET /api/v3/athlete/activities?per_page=$PER_PAGE&page=$page"
  curl_retry -fsS "$STRAVA_API_BASE/athlete/activities?per_page=$PER_PAGE&page=$page" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -o "$TMP/page.json" || die "activities fetch failed (page $page)"

  count="$(jq 'length' "$TMP/page.json" 2>/dev/null || echo 0)"
  [ "$count" -gt 0 ] || { log "page $page empty, stopping"; reached_end=1; break; }

  # jq cannot safely represent every 64-bit JSON integer. Prefer Strava's
  # exact string fields before storing either activity or nested athlete IDs.
  jq -c '
    def exact_id:
      if (.id_str // "") != "" then (.id_str | tostring)
      elif .id != null then (.id | tostring)
      else null end;
    .[]
    | exact_id as $activity_id
    | (if $activity_id != null then .id = $activity_id else . end)
    | if (.athlete | type) == "object" then
        .athlete |= (exact_id as $athlete_id
          | if $athlete_id != null then .id = $athlete_id else . end)
      else . end
  ' "$TMP/page.json" >> "$TMP/all.ndjson"
  log "page $page: $count activities"

  [ "$count" -lt "$PER_PAGE" ] && { log "short page, stopping"; reached_end=1; break; }
  page=$((page + 1))
done
