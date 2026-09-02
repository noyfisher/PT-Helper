# BigQuery views

Console/ad-hoc reporting views over the GA4 export dataset
`pt-helper-dev.analytics_506142273`. One `CREATE OR REPLACE VIEW` per file.

| File | What it reports |
|---|---|
| `v_engagement_daily.sql` | DAU, sessions per user, feature adoption counts |
| `v_funnel_daily.sql` | Unique users reaching each funnel step, per day |
| `v_funnel_summary.sql` | Totals per funnel step with % drop-off (Looker Studio funnel chart) |
| `v_retention_cohorts.sql` | Weekly cohort matrix — signup week vs return week |
| `v_screen_flow_daily.sql` | Consecutive screen_view transitions per day, self-loops excluded |
| `v_user_journey_sankey.sql` | Forward-only flow between funnel steps, source → target → user_count |
| `v_workout_metrics.sql` | Workout completion rate, average duration, skip/swap rates |

`deploy_views.sh` takes no arguments (run it from anywhere — it resolves its own
directory) and pipes each `v_*.sql` through
`bq query --project_id=pt-helper-dev --use_legacy_sql=false`. Needs `gcloud auth login`
with BigQuery access on pt-helper-dev, and the `bq` CLI on PATH.

`functions/src/analytics-pull.ts` — the scheduled job behind the monitoring dashboard —
is the downstream consumer, but its SQL is **ported from these views and inlined** on
purpose, so the job never depends on them being deployed (two intentional divergences
are documented at the queries). Editing a view here does not change the dashboard.
